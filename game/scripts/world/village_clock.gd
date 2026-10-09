class_name VillageClock
extends Node3D
## Keep the generated pedestal; crisp separate dial, numerals and hands replace baked lettering.
var hour_hand: Node3D
var shown_minute:=0.0

func build(model: Node3D) -> void:
	name="LiveClock";model.add_child(self);position=Vector3(0,2.63,.194)
	var dial:=MeshInstance3D.new();dial.name="ClockDial"
	var disc:=CylinderMesh.new();disc.top_radius=.427;disc.bottom_radius=.427;disc.height=.018;disc.radial_segments=96
	dial.mesh=disc;dial.rotation.x=PI*.5;dial.material_override=JapaneseArchitecture._flat(Color(.98,.95,.85));add_child(dial)
	var bezel:=MeshInstance3D.new();bezel.name="ClockBezel"
	var ring:=TorusMesh.new();ring.inner_radius=.427;ring.outer_radius=.445;ring.rings=96;ring.ring_segments=8
	bezel.mesh=ring;bezel.rotation.x=PI*.5;bezel.position.z=.012;bezel.material_override=JapaneseArchitecture._flat(Color(.22,.31,.40));add_child(bezel)
	for index in 60:
		var tick:=MeshInstance3D.new();tick.name="DialTick_%02d"%index
		var shape:=BoxMesh.new();shape.size=Vector3(.010 if index%5==0 else .004,.041 if index%5==0 else .018,.004)
		tick.mesh=shape;tick.material_override=JapaneseArchitecture._flat(Color(.26,.32,.37));tick.position=Vector3(sin(index*TAU/60)*.39,cos(index*TAU/60)*.39,.018);tick.rotation.z=-index*TAU/60;add_child(tick)
	for number in range(1,13):
		var label:=Label3D.new();label.name="ClockNumber_%02d"%number;label.text=str(number);label.font=load("res://assets/fonts/LXGWWenKai-Medium.ttf")
		label.font_size=160;label.pixel_size=.00046;label.outline_size=0;label.modulate=Color(.18,.26,.33);label.double_sided=false
		label.position=Vector3(sin(number*TAU/12)*.322,cos(number*TAU/12)*.322,.023);add_child(label)
	hour_hand=_hand("ClockHourHand",.215,.023,Color(.16,.24,.30),.032)
	var pin:=MeshInstance3D.new();pin.name="ClockCentrePin";var dot:=SphereMesh.new();dot.radius=.025;dot.height=.020;dot.radial_segments=20;pin.mesh=dot
	pin.position.z=.063;pin.material_override=JapaneseArchitecture._flat(Color(.74,.53,.26));add_child(pin)
	set_minute(GameState.minute)

func _hand(label: String,length: float,width: float,colour: Color,z: float) -> Node3D:
	var pivot:=Node3D.new();pivot.name=label;add_child(pivot)
	var hand:=MeshInstance3D.new();hand.name="HandMesh"
	var geometry:=BoxMesh.new();geometry.size=Vector3(width,length+.045,.008);hand.mesh=geometry;hand.position=Vector3(0,length*.5-.022,z)
	hand.material_override=JapaneseArchitecture._flat(colour);pivot.add_child(hand);return pivot

func set_minute(minute: float) -> void:
	shown_minute=minute
	hour_hand.rotation.z=-fposmod(minute,720.0)/720.0*TAU

func _process(_delta: float) -> void:
	set_minute(GameState.minute)
