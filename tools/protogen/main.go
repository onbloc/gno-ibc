// protogen reads .gno source files and generates protobuf encode/decode
// helpers for structs marked with //gno:protobuf.
//
// Field schema is taken from `pb:"<num>,<kind>[,opt=val]..."` struct tags:
//
//	bytes               string or []byte
//	varint              uint64
//	int64               int64 (varint wire, sign extended via uint64 cast)
//	int32               int32 (varint wire)
//	bytes32             [32]byte or named alias (e.g. H256); decode enforces len==32
//	message,enc=F,dec=G nested message; F is `func(T) []byte`, G is `func([]byte) (T, error)`
//
// Generated files sit next to the source as <snake_struct>_pb_gen.gno and rely
// on existing pbAppend*/pbDecode* helpers in the same package (e.g. the ones
// in cometbls/misbehaviour.gno).
package main

import (
	"bytes"
	_ "embed"
	"flag"
	"fmt"
	"go/ast"
	"go/format"
	"go/parser"
	"go/printer"
	"go/token"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strconv"
	"strings"
	"text/template"
)

const protoMarker = "//gno:protobuf"

//go:embed codec.gno.tmpl
var codecTmplSrc string

type kind string

const (
	kindBytes   kind = "bytes"
	kindVarint  kind = "varint"
	kindInt64   kind = "int64"
	kindInt32   kind = "int32"
	kindBytes32 kind = "bytes32"
	kindMessage kind = "message"
)

type Field struct {
	Name   string
	GoType string
	Num    int
	Kind   kind
	EncFn  string
	DecFn  string
}

// ErrName is the lowercase-with-spaces form passed to toBytes32 for
// stable error messages ("contract address", "next validators hash").
func (f *Field) ErrName() string {
	return strings.ReplaceAll(snakeCase(f.Name), "_", " ")
}

type Message struct {
	Pkg    string
	Name   string
	Fields []*Field
}

var codecTmpl = template.Must(template.New("codec.gno.tmpl").Parse(codecTmplSrc))

func main() {
	flag.Parse()
	if flag.NArg() == 0 {
		fmt.Fprintln(os.Stderr, "usage: protogen <pkg-dir> [<pkg-dir>...]")
		os.Exit(2)
	}
	for _, dir := range flag.Args() {
		if err := processDir(dir); err != nil {
			fmt.Fprintf(os.Stderr, "protogen: %s: %v\n", dir, err)
			os.Exit(1)
		}
	}
}

func processDir(dir string) error {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return err
	}
	fset := token.NewFileSet()
	var (
		pkgName string
		msgs    []*Message
	)
	for _, e := range entries {
		name := e.Name()
		if !strings.HasSuffix(name, ".gno") {
			continue
		}
		if strings.HasSuffix(name, "_test.gno") || strings.HasSuffix(name, "_filetest.gno") || strings.HasSuffix(name, "_pb_gen.gno") {
			continue
		}
		src, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			return err
		}
		f, err := parser.ParseFile(fset, name, src, parser.ParseComments)
		if err != nil {
			return fmt.Errorf("parse %s: %w", name, err)
		}
		if pkgName == "" {
			pkgName = f.Name.Name
		}
		for _, decl := range f.Decls {
			gen, ok := decl.(*ast.GenDecl)
			if !ok || gen.Tok != token.TYPE {
				continue
			}
			groupHasMarker := commentGroupHas(gen.Doc, protoMarker)
			for _, spec := range gen.Specs {
				ts, ok := spec.(*ast.TypeSpec)
				if !ok {
					continue
				}
				if !(groupHasMarker || commentGroupHas(ts.Doc, protoMarker)) {
					continue
				}
				st, ok := ts.Type.(*ast.StructType)
				if !ok {
					return fmt.Errorf("%s: %s is marked //gno:protobuf but is not a struct", name, ts.Name.Name)
				}
				m, err := parseStruct(ts.Name.Name, st)
				if err != nil {
					return fmt.Errorf("%s: %w", ts.Name.Name, err)
				}
				m.Pkg = pkgName
				msgs = append(msgs, m)
			}
		}
	}
	sort.Slice(msgs, func(i, j int) bool { return msgs[i].Name < msgs[j].Name })
	for _, m := range msgs {
		out, err := render(m)
		if err != nil {
			return fmt.Errorf("render %s: %w", m.Name, err)
		}
		outPath := filepath.Join(dir, snakeCase(m.Name)+"_pb_gen.gno")
		if err := os.WriteFile(outPath, out, 0o644); err != nil {
			return err
		}
		fmt.Println("wrote", outPath)
	}
	return nil
}

func commentGroupHas(cg *ast.CommentGroup, marker string) bool {
	if cg == nil {
		return false
	}
	for _, c := range cg.List {
		if strings.TrimSpace(c.Text) == marker {
			return true
		}
	}
	return false
}

func parseStruct(name string, st *ast.StructType) (*Message, error) {
	m := &Message{Name: name}
	seenNums := map[int]string{}
	for _, astField := range st.Fields.List {
		if astField.Tag == nil {
			continue
		}
		raw, err := strconv.Unquote(astField.Tag.Value)
		if err != nil {
			return nil, fmt.Errorf("invalid struct tag: %w", err)
		}
		tagVal, ok := reflect.StructTag(raw).Lookup("pb")
		if !ok {
			continue
		}
		if len(astField.Names) == 0 {
			return nil, fmt.Errorf("embedded fields are not supported")
		}
		goType := typeString(astField.Type)
		for _, fname := range astField.Names {
			f, err := parseTag(fname.Name, tagVal)
			if err != nil {
				return nil, fmt.Errorf("field %s: %w", fname.Name, err)
			}
			f.GoType = goType
			if other, dup := seenNums[f.Num]; dup {
				return nil, fmt.Errorf("duplicate field number %d on %s and %s", f.Num, other, fname.Name)
			}
			seenNums[f.Num] = fname.Name
			m.Fields = append(m.Fields, f)
		}
	}
	if len(m.Fields) == 0 {
		return nil, fmt.Errorf("no pb-tagged fields")
	}
	return m, nil
}

func parseTag(fname, tag string) (*Field, error) {
	parts := strings.Split(tag, ",")
	if len(parts) < 2 {
		return nil, fmt.Errorf("tag must be `pb:\"<num>,<kind>[,opt=val]...\"`, got %q", tag)
	}
	num, err := strconv.Atoi(strings.TrimSpace(parts[0]))
	if err != nil || num <= 0 {
		return nil, fmt.Errorf("invalid field number %q", parts[0])
	}
	f := &Field{Name: fname, Num: num}
	switch strings.TrimSpace(parts[1]) {
	case "bytes":
		f.Kind = kindBytes
	case "varint":
		f.Kind = kindVarint
	case "int64":
		f.Kind = kindInt64
	case "int32":
		f.Kind = kindInt32
	case "bytes32":
		f.Kind = kindBytes32
	case "message":
		f.Kind = kindMessage
	default:
		return nil, fmt.Errorf("unknown kind %q", parts[1])
	}
	for _, opt := range parts[2:] {
		opt = strings.TrimSpace(opt)
		k, v, ok := strings.Cut(opt, "=")
		if !ok {
			return nil, fmt.Errorf("invalid option %q (want key=value)", opt)
		}
		switch k {
		case "enc":
			f.EncFn = v
		case "dec":
			f.DecFn = v
		default:
			return nil, fmt.Errorf("unknown option %q", k)
		}
	}
	if f.Kind == kindMessage && (f.EncFn == "" || f.DecFn == "") {
		return nil, fmt.Errorf("kind=message requires enc=<fn> and dec=<fn>")
	}
	return f, nil
}

func render(m *Message) ([]byte, error) {
	var buf bytes.Buffer
	if err := codecTmpl.Execute(&buf, m); err != nil {
		return nil, err
	}
	src := buf.Bytes()
	formatted, err := format.Source(src)
	if err != nil {
		return src, fmt.Errorf("gofmt failed: %w\n--- source ---\n%s", err, src)
	}
	return formatted, nil
}

var typeFset = token.NewFileSet()

// typeString renders a field type back to source form.
func typeString(e ast.Expr) string {
	var buf bytes.Buffer
	if err := printer.Fprint(&buf, typeFset, e); err != nil {
		return fmt.Sprintf("/* unprintable %T */", e)
	}
	return buf.String()
}

func snakeCase(s string) string {
	var b strings.Builder
	for i, r := range s {
		if i > 0 && r >= 'A' && r <= 'Z' {
			b.WriteByte('_')
		}
		if r >= 'A' && r <= 'Z' {
			r += 'a' - 'A'
		}
		b.WriteRune(r)
	}
	return b.String()
}
