package main

import (
	"go/ast"
	"go/parser"
	"go/token"
	"strings"
	"testing"
)

func TestParseTag(t *testing.T) {
	t.Run("message_requires_enc_and_dec", func(t *testing.T) {
		_, err := parseTag("Header", "1,message,enc=pbEncodeHeader")
		if err == nil {
			t.Fatal("expected error for message tag without dec option")
		}
		if !strings.Contains(err.Error(), "requires enc=<fn> and dec=<fn>") {
			t.Fatalf("error got %q", err.Error())
		}
	})

	t.Run("parses_message_options", func(t *testing.T) {
		f, err := parseTag("Header", "1,message,enc=pbEncodeHeader,dec=pbDecodeHeader")
		if err != nil {
			t.Fatalf("parseTag: %v", err)
		}
		if f.Num != 1 || f.Kind != kindMessage || f.EncFn != "pbEncodeHeader" || f.DecFn != "pbDecodeHeader" {
			t.Fatalf("field got %#v", f)
		}
	})
}

func TestParseStructRejectsDuplicateFieldNumbers(t *testing.T) {
	st := parseFirstStruct(t, `package sample
type ClientState struct {
	ChainID string `+"`"+`pb:"1,bytes"`+"`"+`
	Other   string `+"`"+`pb:"1,bytes"`+"`"+`
}`)
	_, err := parseStruct("ClientState", st)
	if err == nil {
		t.Fatal("expected duplicate field number error")
	}
	if !strings.Contains(err.Error(), "duplicate field number 1") {
		t.Fatalf("error got %q", err.Error())
	}
}

func TestSnakeCase(t *testing.T) {
	testCases := map[string]string{
		"ClientState":  "client_state",
		"Misbehaviour": "misbehaviour",
		"H256Value":    "h256_value",
	}
	for in, want := range testCases {
		if got := snakeCase(in); got != want {
			t.Fatalf("snakeCase(%q): got %q want %q", in, got, want)
		}
	}
}

func TestRenderIncludesFieldNumberInWireErrors(t *testing.T) {
	m := &Message{
		Pkg:  "sample",
		Name: "ClientState",
		Fields: []*Field{
			{Name: "ChainID", GoType: "string", Num: 1, Kind: kindBytes},
			{Name: "LatestHeight", GoType: "Height", Num: 6, Kind: kindMessage, EncFn: "pbEncodeHeight", DecFn: "pbDecodeHeight"},
		},
	}
	out, err := render(m)
	if err != nil {
		t.Fatalf("render: %v", err)
	}
	src := string(out)
	for _, want := range []string{
		"pbExpectWire(1, wireType, 2)",
		"pbExpectWire(6, wireType, 2)",
	} {
		if !strings.Contains(src, want) {
			t.Fatalf("rendered source missing %q:\n%s", want, src)
		}
	}
}

func parseFirstStruct(t *testing.T, src string) *ast.StructType {
	t.Helper()

	f, err := parser.ParseFile(token.NewFileSet(), "sample.gno", src, parser.ParseComments)
	if err != nil {
		t.Fatalf("ParseFile: %v", err)
	}
	for _, decl := range f.Decls {
		gen, ok := decl.(*ast.GenDecl)
		if !ok || gen.Tok != token.TYPE {
			continue
		}
		for _, spec := range gen.Specs {
			ts, ok := spec.(*ast.TypeSpec)
			if !ok {
				continue
			}
			st, ok := ts.Type.(*ast.StructType)
			if ok {
				return st
			}
		}
	}
	t.Fatal("no struct found")
	return nil
}
