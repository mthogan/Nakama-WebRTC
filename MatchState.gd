extends Node

signal peers_received(peers)
signal peer_joined(socket, match_id, connected_opponents)
onready var socket = NClient.socket
var connected_opponents : Dictionary
var match_id

enum OP_CODE {
	PEERS = 1,
	JOIN = 2
}
func _ready():
	socket.connect("received_match_state", self, "_on_match_state_received")


func _on_match_state_received(p_state : NakamaRTAPI.MatchData):
#	print("Received match state with opcode %s, data %s" % [p_state.op_code, parse_json(p_state.data)])
	
	match p_state.op_code:
		
		OP_CODE.PEERS:
#			var data = parse_json(p_state.data)
#			var data2 = JSON.parse(p_state.data).result
			var data3 = Marshalls.base64_to_variant(p_state.data, true)
#			print("data: %s" %data.values()[0])
#			print("data2: %s" %data2.result.values()[0])
			print("emit peers_received")
			emit_signal("peers_received", data3)
			
		OP_CODE.JOIN:
			print("emit peer_joined")
			emit_signal("peer_joined")
