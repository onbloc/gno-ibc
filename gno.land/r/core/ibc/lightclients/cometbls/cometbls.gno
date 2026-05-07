package cometbls

import "gno.land/r/union/core"

// var coreAddress address;

func Register(_ realm) {
	core.RegisterClient(cross, "cometbls", core.ILightClient{
		CreateClient: func(clientId core.ClientId, clientStateBytes, consensusStateBytes []byte) {
			println(clientId)
		},
	})
}

type Cometbls struct{}

func (c Cometbls) CreateClient() (Height, string) {}

// func Render(_ string) string {
// 	var s = "registered clients: {";

//     for key := range clientRegistry {
//         s += " "
//         s += key
//     }

//     s += "}"

//     return s
// }
