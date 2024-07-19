extends Node

# Main Menu items.
@onready var _player_name_input = $MainMenu/PanelContainer/MarginContainer/VBoxContainer/PlayerNameInput
@onready var _host_game_btn = $MainMenu/PanelContainer/MarginContainer/VBoxContainer/HostGameBtn
@onready var _ip_address_input = $MainMenu/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/IPAddressInput
@onready var _join_game_btn = $MainMenu/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/JoinGameBtn

# Lobby items.
@onready var _exit_button = $Lobby/RightPanel/ExitButton
@onready var _chat_display_window = $Lobby/RightPanel/ChatDisplay
@onready var _chat_input = $Lobby/RightPanel/ChatEntryContainer/ChatInput
@onready var _chat_send_button = $Lobby/RightPanel/ChatEntryContainer/ChatSendButton
@onready var _ready_button = $Lobby/RightPanel/ReadyButton

# These signals can be connected to by a UI lobby scene or the game scene.
signal player_connected(peer_id, player_info)
signal player_disconnected(peer_id)
signal server_disconnected

const PORT = 7000
const DEFAULT_SERVER_IP = "localhost" # IPv4 localhost
const MAX_CONNECTIONS = 9

# This will contain player info for every player,
# with the keys being each player's unique IDs.
var players = {}

# This is the local player info. This should be modified locally
# before the connection is made. It will be passed to every other peer.
# For example, the value of "name" can be set to something the player
# entered in a UI scene.
var player_info = {
	"joined_order": 0,
	"name": "Name", 
	"faction": "Faction", 
	"status": "Status",
	'color': 'Color'
	}

var PLAYER_COLORS = [
	'#FF6666',
	'#FFB266',
	'#FFFF99',
	'#99FF99',
	'#99CCFF',
	'#B399FF',
	'#E699E6',
	'#FFFFFF',
	'#757575'
]

var players_loaded = 0


func _ready():
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func join_game(address = ""):
	if address.is_empty():
		address = DEFAULT_SERVER_IP
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, PORT)
	if error:
		return error
	multiplayer.multiplayer_peer = peer
	$MainMenu.hide()
	$Lobby.show()
	_update_player_list_display()


func create_game():
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(PORT, MAX_CONNECTIONS)
	if error:
		return error
	multiplayer.multiplayer_peer = peer
	player_info['color'] = assign_color()
	players[1] = player_info
	player_connected.emit(1, player_info)
	$MainMenu.hide()
	$Lobby.show()
	_update_player_list_display()


func remove_multiplayer_peer():
	multiplayer.multiplayer_peer = null


# When the server decides to start the game from a UI scene,
# do Lobby.load_game.rpc(filepath)
@rpc("call_local", "reliable")
func load_game(game_scene_path):
	get_tree().change_scene_to_file(game_scene_path)


# Every peer will call this when they have loaded the game scene.
@rpc("any_peer", "call_local", "reliable")
func player_loaded():
	if multiplayer.is_server():
		players_loaded += 1
		if players_loaded == players.size():
			$/root/Game.start_game()
			players_loaded = 0


# When a peer connects, send them my player info.
# This allows transfer of all desired data for each player, not only the unique ID.
func _on_player_connected(id):
	print('>>> Player connected.')
	player_info['color'] = assign_color()
	_register_player.rpc_id(id, player_info)


@rpc("any_peer", "reliable")
func _register_player(new_player_info):
	var new_player_id = multiplayer.get_remote_sender_id()
	if new_player_info['color'] in PLAYER_COLORS:
		PLAYER_COLORS.erase(new_player_info['color'])
	players[new_player_id] = new_player_info
	player_connected.emit(new_player_id, new_player_info)
	print(players)
	_update_player_list_display()


func _on_player_disconnected(id):
	print('>>> Player disconnected.')
	return_color_to_pool(players[id]['color'])
	players.erase(id)
	player_disconnected.emit(id)
	#print(players)
	_update_player_list_display()


func _on_connected_ok():
	print('>>> Connected - OK.')
	var peer_id = multiplayer.get_unique_id()
	players[peer_id] = player_info
	player_connected.emit(peer_id, player_info)


func _on_connected_fail():
	print('>>> Connected - FAIL.')
	multiplayer.multiplayer_peer = null


func _on_server_disconnected():
	print('>>> Server disconnected.')
	multiplayer.multiplayer_peer = null
	players.clear()
	server_disconnected.emit()


func _update_player_list_display():
	#print(players)
	update_player_rows()


func _on_host_game_btn_pressed():
	var player_name = _player_name_input.text
	print(player_name, ' has hosted a game!')
	player_info['name'] = player_name
	create_game()


func _on_join_game_btn_pressed():
	var player_name = _player_name_input.text
	var ip_address = _ip_address_input.text
	print(player_name, " has joined a game. IP Address: ", ip_address)
	player_info['name'] = player_name
	join_game(ip_address)


@rpc("any_peer", "call_local")
func chat_message(user_dct, message):
	if not message:
		return
	var name_color = user_dct['color']
	_chat_display_window.text += str("[color=", name_color, "]>> ", user_dct['name'], ":[/color] ", message, "\n")


func _on_chat_send_button_pressed():
	rpc("chat_message", player_info, _chat_input.text)
	_chat_input.text = ""


func _unhandled_input(event):
	if event is InputEventKey and event.keycode == KEY_ENTER and _chat_input.text:
		_on_chat_send_button_pressed()


func update_player_rows():
	# Cleanup
	for child in $Lobby/LeftPanel.get_children():
		if child.name != "HeaderRow":
			child.queue_free()
			
	# Add player rows.
	var player_ids = players.keys()
	player_ids.sort()
	for player_id in player_ids:
		var row = HBoxContainer.new()
		var name_card = Label.new()
		var faction_card = Label.new()
		var status_card = Label.new()
		var color_card = Label.new()
		name_card.text = players[player_id]['name']
		faction_card.text = players[player_id]['faction']
		status_card.text = players[player_id]['status']
		color_card.text = players[player_id]['color']
		for card in [name_card, faction_card, status_card, color_card]:
			card.size_flags_horizontal = 3 # Sets the node's size flags to both fill and expand.
			card.horizontal_alignment = 1 # Center
			row.add_child(card)
		$Lobby/LeftPanel.add_child(row)


func assign_color():
	var rand_idx = randi_range(0, len(PLAYER_COLORS)-1)
	var player_color = PLAYER_COLORS[rand_idx]
	PLAYER_COLORS.remove_at(rand_idx)
	print(PLAYER_COLORS, player_color)
	return player_color


func return_color_to_pool(color):
	if color in PLAYER_COLORS:
		return
	PLAYER_COLORS.append(color)
	print(PLAYER_COLORS)

