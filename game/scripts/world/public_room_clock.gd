class_name PublicRoomClock
extends Node3D
var minute_hand: Node3D
var hour_hand: Node3D
var shown_minute := -1
func _ready() -> void:
	name="NeighbourWallClock";set_meta("model_part",true)
	PublicPlaceArt.cylinder(self,"ClockRim",Vector3.ZERO,.19,.035,PublicPlaceArt.wood()).rotation.x=PI*.5
	PublicPlaceArt.cylinder(self,"ClockFace",Vector3(0,0,.023),.17,.006,PublicPlaceArt.matte(Color(.95,.92,.81))).rotation.x=PI*.5
	for index in 12:
		var angle: float=float(index)*TAU/12.0
		var tick:=PublicPlaceArt.box(self,"Tick_%d"%index,Vector3(.009,.025,.006),Vector3(sin(angle)*.145,cos(angle)*.145,.03),PublicPlaceArt.matte(Color(.35,.35,.29)));tick.rotation.z=-angle
	hour_hand=Node3D.new();hour_hand.name="HourHandPivot";add_child(hour_hand)
	minute_hand=Node3D.new();minute_hand.name="MinuteHandPivot";add_child(minute_hand)
	PublicPlaceArt.box(hour_hand,"HourHand",Vector3(.014,.085,.008),Vector3(0,.0425,.04),PublicPlaceArt.matte(Color(.25,.29,.27)))
	PublicPlaceArt.box(minute_hand,"MinuteHand",Vector3(.008,.13,.008),Vector3(0,.065,.05),PublicPlaceArt.matte(Color(.35,.39,.35)))
func _process(_delta: float) -> void:
	var minute: int=int(GameState.minute)
	if minute==shown_minute:return
	shown_minute=minute;minute_hand.rotation.z=-TAU*float(posmod(minute,60))/60.0
	hour_hand.rotation.z=-TAU*fmod(float(minute)/60.0,12.0)/12.0
