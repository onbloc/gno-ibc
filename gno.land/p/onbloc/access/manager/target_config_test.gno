package manager

import "testing"

func TestTargetConfigManagesNilFunctionRolesMap(t *testing.T) {
	targetConfig := &TargetConfig{}

	if targetConfig.functionRole("unset") != AdminRole {
		t.Fatal("unset selector must default to admin role")
	}
	if targetConfig.FunctionRoles == nil {
		t.Fatal("functionRole must initialize function roles map")
	}

	targetConfig.setFunctionRole("a", testRole)
	targetConfig.setFunctionRoles([]Selector{"b", "c"}, 2)

	if targetConfig.functionRole("a") != testRole {
		t.Fatal("single selector role must be configured")
	}
	if targetConfig.functionRole("b") != 2 {
		t.Fatal("first batch selector role must be configured")
	}
	if targetConfig.functionRole("c") != 2 {
		t.Fatal("second batch selector role must be configured")
	}
}

func TestTargetConfigClosed(t *testing.T) {
	targetConfig := NewTargetConfig(false)

	if targetConfig.isClosed() {
		t.Fatal("new target config must use provided closed value")
	}

	targetConfig.setClosed(true)
	if !targetConfig.isClosed() {
		t.Fatal("target config must report updated closed value")
	}
}
