package zkgm

func GetConfig() Config {
	return Config{
		ImplPath:     implPath,
		AllowedImpls: cloneStrings(allowedImpls),
		Paused:       paused,
	}
}

func Render(path string) string {
	if impl == nil {
		return "zkgm: impl not set"
	}
	return impl.Render(gRealm.PkgPath(), path)
}
