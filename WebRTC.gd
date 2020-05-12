extends Node

var peers : Dictionary

var peer_connection : WebRTCPeerConnection
#var _multiplayer : WebRTCMultiplayer = WebRTCMultiplayer.new()
#var configuration = {"iceServers": [{ "urls": [ "stun:stun.example.com:3478" ], }]}
var options = {
	"negotiated": true, # When set to true (default off), means the channel is negotiated out of band. "id" must be set too. data_channel_received will not be called.
	"id": 1, # When "negotiated" is true this value must also be set to the same value on both peer.

#	# Only one of maxRetransmits and maxPacketLifeTime can be specified, not both. They make the channel unreliable (but also better at real time).
#	"maxRetransmits": 1, # Specify the maximum number of attempt the peer will make to retransmits packets if they are not acknowledged.
#	"maxPacketLifeTime": 100, # Specify the maximum amount of time before giving up retransmitions of unacknowledged packets (in milliseconds).
#	"ordered": true, # When in unreliable mode (i.e. either "maxRetransmits" or "maxPacketLifetime" is set), "ordered" (true by default) specify if packet ordering is to be enforced.
#
#	"protocol": "my-custom-protocol", # A custom sub-protocol string for this channel.
}

var socket
var _index
var data_channel: WebRTCDataChannel
var peer_id
var state = 5
var _match_id
var _connected_opponents

enum ConnectionState {
	STATE_NEW = 0, # — The connection is new, data channels and an offer can be created in this state.
	STATE_CONNECTING = 1, # — The peer is connecting, ICE is in progress, none of the transports has failed.
	STATE_CONNECTED = 2, # — The peer is connected, all ICE transports are connected.
	STATE_DISCONNECTED = 3, # — At least one ICE transport is disconnected.
	STATE_FAILED = 4, # — One or more of the ICE transports failed.
	STATE_CLOSED = 5 #— The peer connection is closed (after calling close for example).
}



func _ready():	
	MatchState.connect("peers_received", self, "_on_peers_received")
	MatchState.connect("peer_joined", self, "_on_peer_joined")
	
#	_multiplayer.add_peer(peer_connection, peer_id)
#	_multiplayer.close()
#	_multiplayer.get_peer(peer_id)
#	_multiplayer.get_peers()
#	if _multiplayer.has_peer(peer_id):
#		pass
#	_multiplayer.initialize(peer_id)
#	_multiplayer.remove_peer(peer_id)


#	peer_connection.initialize(configuration)
#	peer_connection.get_connection_state()
#	peer_connection.close()

func _process(_delta):
	match state:
		ConnectionState.STATE_NEW:
			peer_connection.poll()
			if data_channel.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
				while data_channel.get_available_packet_count() > 0:
					print(" received: ", data_channel.get_packet().get_string_from_utf8())


func register(user_id):
	assert(peers.size() < 5) #MAX PLAYER PER GAME
	peer_id = user_id
	peer_connection = WebRTCPeerConnection.new()
	print(peer_connection)
	peer_connection.connect("data_channel_received", self, "_on_data_channel_received")
	peer_connection.connect("ice_candidate_created", self, "_on_ice_candidate_created")
	peer_connection.connect("session_description_created", self, "_on_session_description_created")
	data_channel = peer_connection.create_data_channel("label", options)
	state = 0
	peers[user_id] = peer_connection
	print("registering self %s to peers \n%s" %[peer_id, peers])
	# If it's the second onwards, create an offer

	if peers.size() > 1:
		var offer = peer_connection.create_offer()
		if offer != OK:
			print("%s create offer failed %s" % [peer_connection, offer])
		else:
			print("%s create offer success %s" % [peer_connection, offer])
#		for p in peers:
#			if p != peer_id:
#				var offer = peers[p].create_offer()
#				if offer != OK:
#					print("%s create offer failed %s" % [p, offer])
#				else:
#					print("%s create offer success %s" % [p, offer])

func join(match_id, connected_opponents, user_id):
	peer_id = user_id
	_match_id = match_id
	_connected_opponents = connected_opponents
	var target = connected_opponents
	target.erase(peer_id)
	var data = {"match_id": match_id, "connected_opponents": connected_opponents}
	send_data(match_id, target, 2, JSON.print(data))
	

func _on_session_description_created(type: String, sdp: String):
	for p in peers:
		if p != peer_id:
			var err = peers[p].set_remote_description(type, sdp)
			if err != OK:
				print("failed set SDP of peer:%s " %p)
			else:
				print("succeed set SDP of peer:%s " %p)
				
	
	var err = peer_connection.set_local_description(type, sdp)
	if err != OK:
		print("failed set SDP of self")
	else:
		print("succeed set SDP of self")


func _on_data_channel_received(channel: Object):
	pass

func _on_ice_candidate_created(media: String, index: int, name: String):
	for p in peers:
		if p != peer_id:
			var err = peers[p].add_ice_candidate(media, index, name)
			if err != OK:
				print("ice candidate added to peer:%s failed" %p)
			else:
				print("ice candidate added to peer:%s succeed" %p)

func send_message(message):
	data_channel.put_packet(message.to_utf8())
	
# send data to other client, could be used to do RTC Signaling?
func send_data(match_id, connected_opponents, op_code, data):
	var presences = connected_opponents.values()
	var msg = yield(socket.send_match_state_async(match_id, op_code, data, presences), "completed")
	if msg.is_exception():
		print("An error occured: %s" % msg)
		return
#	print("Succesfully sent message to %s" %presences.values())

func _on_peer_joined(match_id, connected_opponents):
	print("_on_peer_joined")
	var target = connected_opponents
	target.erase(peer_id)
	send_data(match_id, connected_opponents, 1, Marshalls.variant_to_base64(peers, true))
	
func _on_peers_received(new_peers):
	print("_on_peers_received")
	peers = new_peers
	print(peers)
	if peers.has(peer_id):
		print("%s is already in peers" %peer_id)
		return
	else:
		print("%s is not in peers" %peer_id)
		register(peer_id)
		var target = _connected_opponents
		target.erase(peer_id)
		send_data(_match_id, target, 1, Marshalls.variant_to_base64(peers, true))
		

