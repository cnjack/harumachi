extends Node
## Evidence camera: `-- --shots=<dir> [--views=a,b]` renders predefined views to PNG and quits.

const VIEWS := {
	"plaza_moss_close": {"player":Vector3(-1,.1,2),"time":10.5,"camera_at":Vector3(2.5,1.05,4.7),"camera_focus":Vector3(3.7,.55,5.8)},
	"plaza_overview": {"player":Vector3(-1,.1,2),"time":10.5,"camera_at":Vector3(-10,6,-10),"camera_focus":Vector3(4,4.2,7)},
	"plaza_east_edge": {"player":Vector3(-1,.1,2),"time":10.5,"camera_at":Vector3(15,5,8),"camera_focus":Vector3(48,4,31)},
	"plaza_dapple": {"player":Vector3(-1,.1,2),"time":12.0,"camera_at":Vector3(-4,3,1),"camera_focus":Vector3(4,.1,7)},
	"shop_cooperation_note": {"interior":"bakery","at":Vector3(-1.1,.05,1.8),"face":180.0,"time":10.0,"inside_camera":Vector3(-1.1,1.35,2.55),"inside_focus":Vector3(-1.55,1.15,1.35)},
	"direction_sign": {"player":Vector3(20.2,.1,-5.8),"time":10.5,"camera_at":Vector3(20.5,1.9,-5.8),"camera_focus":Vector3(22.6,1.9,-6.2)},
	"direction_sign_back": {"player":Vector3(24.4,.1,-6.2),"time":10.5,"camera_at":Vector3(24.7,1.9,-6.6),"camera_focus":Vector3(22.6,1.9,-6.2)},
	"shop_groceries": {"interior":"store","at":Vector3(.6,.05,1.9),"face":180.0,"pitch":46.0,"dist":8.6,"time":10.0,"inside_camera":Vector3(-.96,1.18,.7),"inside_focus":Vector3(-.96,.78,-.8)},
	"shop_tools": {"interior":"store","at":Vector3(.6,.05,1.9),"face":180.0,"pitch":46.0,"dist":8.6,"time":10.0,"inside_camera":Vector3(-3.1,1.3,-.9),"inside_focus":Vector3(-4.7,.6,-1.35)},
	"shop_food": {"interior":"store","at":Vector3(.6,.05,1.9),"face":180.0,"pitch":46.0,"dist":8.6,"time":10.0,"inside_camera":Vector3(1.85,1.05,4.3),"inside_focus":Vector3(1.85,.63,3.0)},
	"shop_tv": {"interior":"store","at":Vector3(.6,.05,1.9),"face":180.0,"pitch":46.0,"dist":8.6,"time":10.0,"inside_camera":Vector3(3.9,1.95,-.78),"inside_focus":Vector3(5.05,1.92,-.8)},
	"shop_tv_side": {"interior":"store","at":Vector3(.6,.05,1.9),"face":180.0,"pitch":46.0,"dist":8.6,"time":10.0,"inside_camera":Vector3(4.20,2.05,.02),"inside_focus":Vector3(5.05,1.93,-.8)},
	"shop_tv_static": {"interior":"store","at":Vector3(.6,.05,1.9),"face":180.0,"pitch":46.0,"dist":8.6,"time":10.0,"tv_signal":12.08,"inside_camera":Vector3(3.9,1.95,-.78),"inside_focus":Vector3(5.05,1.92,-.8)},
	"shop_tv_rain": {"interior":"store","at":Vector3(.6,.05,1.9),"face":180.0,"pitch":46.0,"dist":8.6,"time":10.0,"weather":"rain","inside_camera":Vector3(3.9,1.95,-.78),"inside_focus":Vector3(5.05,1.92,-.8)},
	"shop_pastries": {"interior":"bakery","at":Vector3(.0,.05,2.0),"face":180.0,"pitch":46.0,"dist":8.6,"time":9.0,"inside_camera":Vector3(-2.7,1.20,1.15),"inside_focus":Vector3(-2.7,.76,-.3)},
	"shop_cakes": {"interior":"bakery","at":Vector3(.0,.05,2.0),"face":180.0,"pitch":46.0,"dist":8.6,"time":9.0,"inside_camera":Vector3(.48,1.45,2.15),"inside_focus":Vector3(.48,.99,.53)},
	"shop_poster": {"interior":"bakery","at":Vector3(.0,.05,2.0),"face":180.0,"pitch":46.0,"dist":8.6,"time":9.0,"inside_camera":Vector3(4.1,2.08,.8),"inside_focus":Vector3(5.46,2.05,.8)},
	"shop_store_poster": {"interior":"store","at":Vector3(.6,.05,1.9),"face":180.0,"pitch":46.0,"dist":8.6,"time":10.0,"inside_camera":Vector3(2.2,2.20,-2.45),"inside_focus":Vector3(2.2,2.20,-3.86)},
	"shop_tools_poster": {"interior":"store","at":Vector3(.6,.05,1.9),"face":180.0,"pitch":46.0,"dist":8.6,"time":10.0,"inside_camera":Vector3(-4.0,2.15,-2.35),"inside_focus":Vector3(-5.34,2.15,-2.35)},
	"life_bunting": {"player":Vector3(6.3,.1,10.4),"time":10.5,"camera_at":Vector3(7,1.45,7.5),"camera_focus":Vector3(5.5,1.8,11.2),"place_fixture":true,"settle_seconds":3.0},
	"life_lantern": {"player":Vector3(9,.1,10.4),"time":18.5,"camera_at":Vector3(11.3,1.8,10.7),"camera_focus":Vector3(9.5,1.65,12.4),"place_fixture":true,"settle_seconds":3.0},
	"life_chime": {"player":Vector3(-1,.1,-14),"time":10.5,"camera_at":Vector3(-1.1,2.22,-14.3),"camera_focus":Vector3(-1.25,2.22,-15.7),"settle_seconds":3.0},
	"life_daisies": {"player":Vector3(-7.8,.1,20.5),"time":10.5,"camera_at":Vector3(-8.6,.65,20.7),"camera_focus":Vector3(-7.8,.23,22.0),"settle_seconds":2.0},
	"life_reeds": {"farm":true,"player":Vector3(137,.1,15),"time":10.5,"camera_at":Vector3(139,1.6,15),"camera_focus":Vector3(133,.5,17),"settle_seconds":3.0},
	"life_rain_bank": {"farm":true,"player":Vector3(137,.1,15),"weather":"rain","time":10.5,"camera_at":Vector3(139,1.6,15),"camera_focus":Vector3(133,.5,17),"settle_seconds":3.0},
	"life_sunny_sky": {"player":Vector3(-1,.1,2),"time":10.5,"camera_at":Vector3(-1,3,2),"camera_focus":Vector3(-15,11,14),"settle_seconds":2.0},
	"life_rain_sky": {"player":Vector3(-1,.1,2),"weather":"rain","time":10.5,"camera_at":Vector3(-1,3,2),"camera_focus":Vector3(-15,11,14),"settle_seconds":2.0},
	"life_sun": {"player":Vector3(-1,.1,2),"time":10.5,"camera_at":Vector3(-1,3,2),"camera_focus":Vector3(-15,11,14),"sun_view":true,"settle_seconds":2.0},
	"life_leaves": {"player":Vector3(1.5,.1,4),"time":10.5,"camera_at":Vector3(-1.5,1.9,1),"camera_focus":Vector3(4,3.4,7),"settle_seconds":7.0},
	"life_cat": {"player":Vector3(19.7,.1,56),"time":10.5,"camera_at":Vector3(19,1,53.4),"camera_focus":Vector3(19.8,.2,55.0),"settle_seconds":4.0},
	"hero_under_tree": {"actors":true,"player":Vector3(1.5,.1,4.0),"time":10.5,"camera_at":Vector3(-1.5,1.9,1.0),"camera_focus":Vector3(4,3.4,7)},
	"hero_reference": {"player":Vector3(-1,.1,2),"time":10.5,"camera_at":Vector3(-4.7,2.2,2.0),"camera_focus":Vector3(4,3.6,7)},
	"hero_canopy": {"player":Vector3(1.5,.1,4.0),"time":10.5,"camera_at":Vector3(-4,5,-3),"camera_focus":Vector3(4,4.7,7)},
	"polish_tree": {"player":Vector3(-1,.1,2),"time":10.5,"camera_at":Vector3(-3,3.7,-2),"camera_focus":Vector3(4,3.4,7)},
	"plaza_drum_close": {"player":Vector3(-5.2,.1,18.6),"time":10.5,"camera_at":Vector3(-6.5,1.15,19.05),"camera_focus":Vector3(-7.7,.72,20.4)},
	"plaza_fish_close": {"player":Vector3(-5.2,.1,18.6),"time":10.5,"camera_at":Vector3(-5.8,1.0,16.9),"camera_focus":Vector3(-8.1,.4,16.9)},
	"plaza_grape_close": {"player":Vector3(-5.2,.1,18.6),"time":10.5,"camera_at":Vector3(-5.6,2.7,10.5),"camera_focus":Vector3(-9.8,2.9,13.2)},
	"plaza_lawn_close": {"player":Vector3(-5.2,.1,18.6),"time":10.5,"camera_at":Vector3(-3.7,.6,18.8),"camera_focus":Vector3(-6.4,.07,19.4)},
	"plaza_footing_close": {"player":Vector3(-5.2,.1,18.6),"time":10.5,"camera_at":Vector3(-7,.6,23),"camera_focus":Vector3(-7.4,.15,24.2)},
	"plaza_tree_dusk": {"player":Vector3(-1,.1,2),"time":17.3,"camera_at":Vector3(-3,3.7,-2),"camera_focus":Vector3(4,3.4,7)},
	"plaza_tree_night": {"player":Vector3(-1,.1,2),"time":19.5,"camera_at":Vector3(-3,3.7,-2),"camera_focus":Vector3(4,3.4,7)},
	"plaza_tree_front": {"player":Vector3(-1,.1,2),"time":10.5,"camera_at":Vector3(4,3.5,-4),"camera_focus":Vector3(4,3.8,7)},
	"plaza_tree_back": {"player":Vector3(-1,.1,2),"time":10.5,"camera_at":Vector3(4,3.5,18),"camera_focus":Vector3(4,3.8,7)},
	"plaza_tree_left": {"player":Vector3(-1,.1,2),"time":10.5,"camera_at":Vector3(-7,3.5,7),"camera_focus":Vector3(4,3.8,7)},
	"plaza_tree_right": {"player":Vector3(-1,.1,2),"time":10.5,"camera_at":Vector3(15,3.5,7),"camera_focus":Vector3(4,3.8,7)},
	"plaza_tree_root": {"player":Vector3(-1,.1,2),"time":10.5,"camera_at":Vector3(1.3,1.25,3.5),"camera_focus":Vector3(4,1.0,7)},
	"polish_sit_cat": {"player":Vector3(19.7,.1,10.6),"time":10.5,"camera_at":Vector3(20.4,1.55,12.1),"camera_focus":Vector3(22.2,1.35,10.6)},
	"detail_arrival_road": {"player":Vector3(-46,.1,-9.5),"time":9.5,"camera_at":Vector3(-49,3.3,-3),"camera_focus":Vector3(-68,1,-11)},
	"detail_bus_front": {"player":Vector3(-42,.1,-9),"time":10.5,"camera_at":Vector3(-38.5,2.0,-8),"camera_focus":Vector3(-44,1.3,-11.3)},
	"detail_clock": {"player":Vector3(-1,.1,-7.1),"time":10.5,"camera_at":Vector3(-1,2.75,-7.4),"camera_focus":Vector3(-1,2.65,-5)},
	"detail_wall": {"player":Vector3(2,.1,-6.5),"time":10.5,"camera_at":Vector3(10.6,1.24,-6.9),"camera_focus":Vector3(12.6,.85,-5.4)},
	"detail_ground": {"player":Vector3(6,.1,4),"time":10.5,"camera_at":Vector3(3.6,.8,2.8),"camera_focus":Vector3(6,.05,5)},
	"detail_sandpit": {"player":Vector3(-6,.1,2.4),"time":10.5,"camera_at":Vector3(-5.1,1.7,2.0),"camera_focus":Vector3(-6.8,.3,4.4)},
	"detail_bus_stop": {"player":Vector3(-43,.1,-8),"time":10.5,"camera_at":Vector3(-38,2.4,-10),"camera_focus":Vector3(-44,1.2,-4.6)},
	"residential_day": {"player":Vector3(19.7,.1,56),"time":10.5,"camera_at":Vector3(19.7,3.4,34),"camera_focus":Vector3(20,2.8,65)},
	"residential_sunset": {"player":Vector3(19.7,.1,60),"time":17.3,"camera_at":Vector3(19.7,2.2,68),"camera_focus":Vector3(20,2.5,39)},
	"residential_overview": {"player":Vector3(19.7,.1,56),"time":10.5,"camera_at":Vector3(-2,22,89),"camera_focus":Vector3(20,0,53)},
	"bus_station": {"player":Vector3(-41,.1,-9.5),"time":9.0,"camera_at":Vector3(-39,2.5,-5.9),"camera_focus":Vector3(-45,1.4,-11.3)},
	"placement_barrel": {"player":Vector3(19.7,.1,12.4),"time":10.5,"camera_at":Vector3(20.0,1.85,11.1),"camera_focus":Vector3(22.5,.70,13.0)},
	"placement_barrel_garden": {"player":Vector3(20.7,.1,14.2),"time":10.5,"camera_at":Vector3(20.7,1.45,14.5),"camera_focus":Vector3(23.4,.65,12.3)},
	"placement_rocks": {"player":Vector3(16,.1,7.7),"time":10.5,"camera_at":Vector3(14.3,1.9,7.45),"camera_focus":Vector3(16,.45,10.8)},
	"placement_sleep_cat": {"player":Vector3(12.6,.1,-6.6),"time":10.5,"camera_at":Vector3(11.9,1.10,-6.70),"camera_focus":Vector3(12.6,.86,-5.42)},
	"placement_north_roots": {"player":Vector3(-38,.1,-23.7),"time":10.5,"camera_at":Vector3(-40.5,1.8,-24.4),"camera_focus":Vector3(-36,1.8,-31)},
	"placement_cat_side": {"player":Vector3(19.7,.1,10.6),"time":10.5,"camera_at":Vector3(20.4,1.55,12.1),"camera_focus":Vector3(22.2,1.35,10.6)},
	"placement_lamp_box": {"player":Vector3(-15.6,.1,-7.7),"time":10.5,"camera_at":Vector3(-14.3,1.6,-9.1),"camera_focus":Vector3(-16.0,.70,-6.3)},
	"display_bakery_front": {"player":Vector3(-24,0.1,-13.2),"time":10.5,"camera_at":Vector3(-24.65,1.75,-13.60),"camera_focus":Vector3(-24.65,1.55,-16.10)},
	"display_bakery_oblique": {"player":Vector3(-24,0.1,-13.2),"time":10.5,"camera_at":Vector3(-26.2,1.75,-14.1),"camera_focus":Vector3(-24.65,1.48,-16.3)},
	"display_florist_oblique": {"player":Vector3(-12,0.1,-13.2),"time":10.5,"camera_at":Vector3(-12.0,1.75,-14.1),"camera_focus":Vector3(-10.8,1.15,-16.2)},
	"display_store_oblique": {"player":Vector3(-36,0.1,-13.2),"time":10.5,"camera_at":Vector3(-37.0,1.8,-14.1),"camera_focus":Vector3(-35.5,1.30,-17.0)},
	"display_zakka_oblique": {"player":Vector3(0,0.1,-13.2),"time":10.5,"camera_at":Vector3(-2.4,1.6,-14.1),"camera_focus":Vector3(-.8,1.05,-16.5)},
	"display_florist_night": {"player":Vector3(-12,0.1,-13.2),"time":21.0,"camera_at":Vector3(-10.7,1.8,-13.55),"camera_focus":Vector3(-10.7,1.2,-15.9)},
	"trees_boundary_front": {"player":Vector3(-3,0.1,-7),"time":10.5,"camera_at":Vector3(-7,3.0,5),"camera_focus":Vector3(-24,4.5,15)},
	"trees_boundary_side": {"player":Vector3(-3,0.1,-7),"time":10.5,"camera_at":Vector3(-5,3.0,8),"camera_focus":Vector3(-39,4.2,15)},
	"trees_north_close": {"player":Vector3(-12,0.1,-13.2),"time":10.5,"camera_at":Vector3(-16,2.5,-26),"camera_focus":Vector3(-29,4.2,-32)},
	"near_bakery_material": {"player": Vector3(-23.12, 0.1, -13.2), "time": 10.5, "camera_at": Vector3(-23.5, 1.65, -13.85), "camera_focus": Vector3(-23.5, 1.4, -16.0)},
	"near_florist_material": {"player": Vector3(-12, 0.1, -13.2), "time": 10.5, "camera_at": Vector3(-10.7, 1.8, -13.55), "camera_focus": Vector3(-10.7, 1.6, -15.9)},
	"near_zakka_material": {"player": Vector3(0, 0.1, -13.2), "time": 10.5, "camera_at": Vector3(-0.4, 1.7, -14.05), "camera_focus": Vector3(-0.4, 1.5, -16.1)},
	"near_post_material": {"player": Vector3(12.5, 0.1, -13.2), "time": 10.5, "camera_at": Vector3(13.3, 1.7, -13.55), "camera_focus": Vector3(13.3, 1.5, -15.6)},
	"near_machiya_material": {"player": Vector3(38.2, 0.1, -13.2), "time": 10.5, "camera_at": Vector3(38.3, 1.7, -13.4), "camera_focus": Vector3(38.3, 1.5, -15.8)},
	"near_residence_material": {"player": Vector3(33.3, 0.1, -13.2), "time": 10.5, "camera_at": Vector3(33.5, 1.7, -13.2), "camera_focus": Vector3(33.5, 1.4, -15.6)},
	"near_family_material": {"player": Vector3(18, 0.1, 26.5), "time": 10.5, "camera_at": Vector3(18.0, 1.7, 25.8), "camera_focus": Vector3(20.15, 1.5, 25.8)},
	"lake_overlook": {"farm": true,"player":Vector3(80, .2, -12),"time":10.0,"camera_at":Vector3(68,12,-28),"camera_focus":Vector3(104,0,20)},
	"lake_pier": {"farm":true,"player":Vector3(94,.2,44.5),"time":16.3,"camera_at":Vector3(87,3.8,49),"camera_focus":Vector3(99,0,21)},
	"river_bend": {"farm":true,"player":Vector3(48,.2,18),"time":10.0,"camera_at":Vector3(38,5.5,12),"camera_focus":Vector3(58,0,26)},
	"lake_evening": {"farm":true,"player":Vector3(115,.2,48),"time":18.5,"camera_at":Vector3(126,4.5,52),"camera_focus":Vector3(100,0,17)},
	"identity_street_day": {"player": Vector3(-30, 0.1, -10), "time": 10.5, "camera_at": Vector3(-42, 3.3, -8.5), "camera_focus": Vector3(-15, 2.5, -17.0)},
	"identity_street_dusk": {"player": Vector3(-30, 0.1, -10), "time": 18.5, "camera_at": Vector3(-42, 3.3, -8.5), "camera_focus": Vector3(-15, 2.5, -17.0)},
	"identity_home_day": {"player": Vector3(20, 0.1, 5.5), "time": 10.5, "camera_at": Vector3(17.9, 3.65, 0), "camera_focus": Vector3(25.8, 2.8, 5.6)},
	"identity_home_night": {"player": Vector3(20, 0.1, 5.5), "time": 20.4, "camera_at": Vector3(17.9, 3.65, 0), "camera_focus": Vector3(25.8, 2.8, 5.6)},
	"identity_pig_near": {"player": Vector3(20, 0.1, 5.5), "time": 10.5, "camera_at": Vector3(22.25, 1.22, 4.9), "camera_focus": Vector3(24.14, 0.65, 4.92)},
	"identity_florist_near": {"player": Vector3(-12, 0.1, -13), "time": 10.5, "camera_at": Vector3(-11.4, 2.4, -13.2), "camera_focus": Vector3(-12.8, 1.4, -17.1)},
	"identity_zakka_near": {"player": Vector3(0, 0.1, -13), "time": 10.5, "camera_at": Vector3(-1.8, 2.2, -13.4), "camera_focus": Vector3(-0.3, 1.6, -16.65)},
	"identity_produce_open": {"player": Vector3(-36, 0.1, -14), "time": 10.5, "camera_at": Vector3(-38, 1.70, -15.1), "camera_focus": Vector3(-37.7, 1.00, -16.19)},
	"identity_produce_closed": {"player": Vector3(-36, 0.1, -14), "time": 19.5, "camera_at": Vector3(-38, 1.70, -15.1), "camera_focus": Vector3(-37.7, 1.00, -16.19)},
	"identity_modern_home": {"player": Vector3(19.7, 0.1, 24), "time": 10.5, "camera_at": Vector3(16, 4.2, 20), "camera_focus": Vector3(24.2, 2.7, 26.5)},
	"identity_apartment_night": {"player": Vector3(25.5, 0.1, -12), "time": 20.4, "camera_at": Vector3(17, 4.9, -8), "camera_focus": Vector3(25.5, 3, -18.4)},
	"near_apartment_ground": {"player": Vector3(25.5, 0.1, -12), "time": 10.5, "camera_at": Vector3(27.0, 1.8, -14.0), "camera_focus": Vector3(26.4, 1.45, -16.0)},
	"near_apartment_rail": {"player": Vector3(25.5, 0.1, -12), "time": 10.5, "camera_at": Vector3(24.0, 4.05, -13.7), "camera_focus": Vector3(24.0, 3.9, -15.83)},
	"near_hall_door": {"player": Vector3(-23.2, 0.1, -8), "time": 10.5, "camera_at": Vector3(-24.0, 1.85, -5.6), "camera_focus": Vector3(-23.2, 1.5, -3.7)},
	"near_home_door": {"player": Vector3(20, 0.1, 5.9), "time": 10.5, "camera_at": Vector3(21.8, 1.8, 5.0), "camera_focus": Vector3(24.05, 1.3, 5.9)},
	"near_engawa_door": {"player": Vector3(-35, 0.1, -10), "time": 10.5, "camera_at": Vector3(-34.1, 1.8, -6.25), "camera_focus": Vector3(-35, 1.4, -4.2)},
	"near_produce_left": {"player": Vector3(-36, 0.1, -14.4), "time": 10.5, "camera_at": Vector3(-37.9, 1.55, -14.0), "camera_focus": Vector3(-37.9, 0.95, -16.15)},
	"near_produce_right": {"player": Vector3(-36, 0.1, -14.4), "time": 10.5, "camera_at": Vector3(-31.8, 1.8, -16.3), "camera_focus": Vector3(-33.45, 0.95, -16.2)},
	"near_produce_night": {"player": Vector3(-36, 0.1, -14.4), "time": 19.5, "camera_at": Vector3(-37.9, 1.55, -14.0), "camera_focus": Vector3(-37.9, 0.95, -16.15)},
	"audit_home": {"player": Vector3(20, 0.1, 5.5), "time": 10.5, "camera_at": Vector3(14, 6.5, -4), "camera_focus": Vector3(26.8, 2.8, 5.5)},
	"audit_apartment": {"player": Vector3(25.5, 0.1, -9), "time": 10.5, "camera_at": Vector3(17, 6.8, -5), "camera_focus": Vector3(25.5, 3, -18.4)},
	"audit_engawa": {"player": Vector3(-35, 0.1, -10), "time": 10.5, "camera_at": Vector3(-44, 4.8, -14), "camera_focus": Vector3(-35, 2, -3)},
	"audit_hall": {"player": Vector3(-23.2, 0.1, -8), "time": 10.5, "camera_at": Vector3(-32, 5.5, -15), "camera_focus": Vector3(-23.2, 2.5, -0.1)},
	"audit_hall_back": {"player": Vector3(-23.2, 0.1, -8), "time": 10.5, "camera_at": Vector3(-33, 5.5, 14), "camera_focus": Vector3(-23.2, 2.5, -0.1)},
	"audit_shed": {"farm": true, "player": Vector3(-10.6, 0.1, -4), "time": 10.5, "camera_at": Vector3(-6, 2.8, -2), "camera_focus": Vector3(-10.6, 1.2, -8.2)},
	"audit_cats": {"player": Vector3(22.2, 0.1, 10.6), "time": 10.5, "camera_at": Vector3(19.6, 1.7, 11.6), "camera_focus": Vector3(22.2, 1.35, 10.6)},
	"guide_sign_front": {"player": Vector3(9.5, 0.1, -13.7), "yaw": 345.0, "pitch": 10.0, "dist": 2.1, "face": 180.0, "time": 10.0, "camera_at": Vector3(10.0, 0.95, -12.9), "camera_focus": Vector3(9.5, 0.52, -14.8)},
	"guide_sign_back": {"player": Vector3(9.5, 0.1, -14.8), "yaw": 165.0, "pitch": 10.0, "dist": 2.1, "face": 0.0, "time": 10.0, "camera_at": Vector3(8.8, 0.95, -15.6), "camera_focus": Vector3(9.5, 0.52, -14.8)},
	"bakery_order_ui": {"bakery_fixture": 1, "panel": ["open_bakery_order", []], "day": 4, "time": 10.0},
	"bakery_menu_old": {"bakery_fixture": 0, "interior": "bakery", "at": Vector3(-2.35, 0.05, 2.7), "face": -90.0, "pitch": 22.0, "dist": 4.3, "time": 10.0},
	"bakery_menu_new": {"bakery_fixture": 1, "interior": "bakery", "at": Vector3(-2.35, 0.05, 2.7), "face": -90.0, "pitch": 22.0, "dist": 4.3, "time": 10.0},
	"bakery_market": {"bakery_fixture": 1, "player": Vector3(3.4, 0.1, 12.6), "yaw": 200.0, "pitch": 18.0, "dist": 5.0, "face": 0.0, "day": 10, "time": 18.0, "phase": "market"},
	"forest_w_close": {"farm": true, "player": Vector3(-27.8, 0.1, -2.0), "yaw": 110.0, "pitch": 8.0, "dist": 4.5, "face": -90.0, "time": 13.35},
	"forest_n_close": {"farm": true, "player": Vector3(-15.0, 0.1, -14.5), "yaw": 20.0, "pitch": 8.0, "dist": 4.5, "face": 180.0, "time": 13.35},
	"spawn": {"player": Vector3(-41.0, 0.1, -9.5), "yaw": 270.0, "pitch": 32.0, "dist": 6.5, "face": 90.0},
	"street_east": {"player": Vector3(-30.0, 0.1, -10.5), "yaw": 250.0, "pitch": 22.0, "dist": 8.0, "face": 80.0},
	"street_west": {"player": Vector3(10.0, 0.1, -11.0), "yaw": 75.0, "pitch": 20.0, "dist": 8.0, "face": -90.0},
	"courtyard": {"player": Vector3(-3.0, 0.1, -1.0), "yaw": 190.0, "pitch": 34.0, "dist": 9.0, "face": 10.0},
	"garden": {"player": Vector3(10.0, 0.1, 14.5), "yaw": 220.0, "pitch": 30.0, "dist": 7.0, "face": 60.0},
	"lane": {"player": Vector3(19.7, 0.1, -3.0), "yaw": 180.0, "pitch": 28.0, "dist": 8.0, "face": 0.0},
	"board": {"player": Vector3(-6.0, 0.1, -9.0), "yaw": 20.0, "pitch": 22.0, "dist": 6.0, "face": 180.0},
	"bakery": {"player": Vector3(-23.0, 0.1, -12.0), "yaw": 10.0, "pitch": 18.0, "dist": 6.5, "face": 180.0},
	"mg_stations": {"player": Vector3(-5.2, 0.1, 18.6), "yaw": 70.0, "pitch": 30.0, "dist": 7.5, "face": -110.0},
	# house views: "house" = house-local player position; the rig keeps the fixed diorama yaw
	"build_sign": {"player": Vector3(-2.6, 0.1, 4.2), "yaw": 0.0, "pitch": 12.0, "dist": 3.2, "face": 180.0},
	"farm_entry": {"farm": true, "player": Vector3(-19.0, 0.1, 0.4), "yaw": 250.0, "pitch": 22.0, "dist": 9.0, "face": 80.0, "time": 10.0, "demo": true},
	"farm_field": {"farm": true, "player": Vector3(0.0, 0.1, -0.4), "yaw": 180.0, "pitch": 38.0, "dist": 8.5, "face": 180.0, "time": 11.0, "demo": true},
	"farm_river": {"farm": true, "player": Vector3(3.0, 0.1, 11.6), "yaw": 330.0, "pitch": 14.0, "dist": 7.5, "face": 20.0, "time": 17.6, "demo": true},
	"farm_bridge": {"farm": true, "player": Vector3(0.0, 0.1, 21.4), "yaw": 180.0, "pitch": 20.0, "dist": 8.0, "face": 180.0, "time": 12.5, "demo": true},
	"farm_gh": {"farm": true, "player": Vector3(11.8, 0.1, -2.6), "yaw": 160.0, "pitch": 30.0, "dist": 6.0, "face": 180.0, "time": 13.0, "demo": true},
	"farm_night": {"farm": true, "player": Vector3(-8.0, 0.1, 0.6), "yaw": 200.0, "pitch": 26.0, "dist": 9.0, "face": 160.0, "time": 21.5, "demo": true},
	"farm_rain": {"farm": true, "player": Vector3(0.0, 0.1, -0.4), "yaw": 200.0, "pitch": 30.0, "dist": 9.0, "face": 180.0, "time": 11.0, "weather": "rain", "demo": true},
	"town_morning": {"player": Vector3(-3.0, 0.1, -1.0), "yaw": 190.0, "pitch": 30.0, "dist": 9.0, "face": 10.0, "time": 6.9},
	"town_noon": {"player": Vector3(-3.0, 0.1, -1.0), "yaw": 190.0, "pitch": 30.0, "dist": 9.0, "face": 10.0, "time": 12.0},
	"town_dusk": {"player": Vector3(-3.0, 0.1, -1.0), "yaw": 190.0, "pitch": 22.0, "dist": 9.0, "face": 10.0, "time": 18.8},
	"town_night": {"player": Vector3(-20.0, 0.1, -10.5), "yaw": 250.0, "pitch": 18.0, "dist": 8.0, "face": 80.0, "time": 21.2},
	"town_rain": {"player": Vector3(-20.0, 0.1, -10.5), "yaw": 250.0, "pitch": 18.0, "dist": 8.0, "face": 80.0, "time": 11.0, "weather": "rain"},
	"town_cloudy": {"player": Vector3(-3.0, 0.1, -1.0), "yaw": 190.0, "pitch": 30.0, "dist": 9.0, "face": 10.0, "time": 14.0, "weather": "cloudy"},
	"court_plot": {"player": Vector3(12.0, 0.1, 14.6), "yaw": 180.0, "pitch": 34.0, "dist": 5.5, "face": 180.0, "time": 10.5, "demo": true},
	"house_yard": {"house": Vector3(2.5, -0.4, -6.2), "pitch": 50.0, "dist": 9.2, "face": 180.0, "time": 9.5, "demo": true},
	"house_night": {"house": Vector3(2.2, 0.0, 0.1), "pitch": 50.0, "dist": 9.2, "face": 180.0, "time": 21.0},
	"farm_gate": {"farm": true, "player": Vector3(-21.0, 0.1, 0.6), "yaw": 110.0, "pitch": 18.0, "dist": 8.5, "face": -90.0, "time": 10.0, "demo": true},
	"farm_meadow": {"farm": true, "player": Vector3(-14.0, 0.1, 8.0), "yaw": 150.0, "pitch": 24.0, "dist": 8.0, "face": 40.0, "time": 9.5, "demo": true},
	"farm_farbank": {"farm": true, "player": Vector3(0.0, 0.1, 24.0), "yaw": 20.0, "pitch": 22.0, "dist": 9.0, "face": 180.0, "time": 16.6, "demo": true},
	"farm_bridge2": {"farm": true, "player": Vector3(0.0, 0.8, 16.0), "yaw": 250.0, "pitch": 16.0, "dist": 9.5, "face": 0.0, "time": 11.0, "demo": true},
	"town_store": {"player": Vector3(-36.0, 0.1, -11.5), "yaw": 180.0, "pitch": 14.0, "dist": 7.5, "face": 180.0, "time": 10.0},
	"npc_wave": {"player": Vector3(-6.0, 0.1, -9.0), "yaw": 0.0, "pitch": 6.0, "dist": 7.5, "face": 0.0, "time": 11.0, "gesture": "wave"},
	"npc_wave_close": {"player": Vector3(-6.0, 0.1, -9.0), "yaw": 0.0, "pitch": 6.0, "dist": 4.2, "face": 0.0, "time": 11.0, "gesture": "wave"},
	"npc_bow": {"player": Vector3(-6.0, 0.1, -9.0), "yaw": 0.0, "pitch": 6.0, "dist": 7.5, "face": 0.0, "time": 11.0, "gesture": "bow"},
	"npc_cheer": {"player": Vector3(-6.0, 0.1, -9.0), "yaw": 0.0, "pitch": 6.0, "dist": 7.5, "face": 0.0, "time": 11.0, "gesture": "cheer"},
	"roster_wave": {"player": Vector3(15.0, 0.1, -9.0), "time": 11.0, "gesture": "wave", "include_player": true, "camera_at": Vector3(15.0, 2.0, -3.2), "camera_focus": Vector3(15.0, 1.0, -10.0), "actors": true},
	"roster_walk": {"player": Vector3(15.0, 0.1, -9.0), "time": 11.0, "gesture": "walk", "include_player": true, "camera_at": Vector3(15.0, 2.0, -3.2), "camera_focus": Vector3(15.0, 1.0, -10.0), "actors": true},
	"roster_dance": {"player": Vector3(15.0, 0.1, -9.0), "time": 11.0, "gesture": "dance", "include_player": true, "camera_at": Vector3(15.0, 2.0, -3.2), "camera_focus": Vector3(15.0, 1.0, -10.0), "actors": true},
	"town_east": {"player": Vector3(36.5, 0.1, -10.2), "yaw": 250.0, "pitch": 16.0, "dist": 8.0, "face": 90.0, "time": 10.0},
	"fest_tanabata": {"player": Vector3(-1.0, 0.1, 1.6), "yaw": 0.0, "pitch": 18.0, "dist": 8.5, "face": 180.0, "time": 19.8, "day": 4},
	"fest_contest": {"player": Vector3(-6.0, 0.1, 5.4), "yaw": 180.0, "pitch": 24.0, "dist": 7.0, "face": 0.0, "time": 11.0, "day": 11},
	"fest_natsu": {"player": Vector3(-2.0, 0.1, 11.0), "yaw": 180.0, "pitch": 20.0, "dist": 10.0, "face": 0.0, "time": 19.9, "day": 17},
	"fest_natsu_close": {"player": Vector3(-1.0, 0.1, 13.0), "yaw": 150.0, "pitch": 8.0, "dist": 5.5, "face": 0.0, "time": 20.3, "day": 17},
	"fest_hanabi": {"farm": true, "player": Vector3(4.0, 0.1, 11.2), "yaw": 170.0, "pitch": -4.0, "dist": 7.0, "face": 0.0, "time": 19.8, "day": 24, "fireworks": true},
	"fest_obon": {"farm": true, "player": Vector3(2.0, 0.1, 11.8), "yaw": 160.0, "pitch": 16.0, "dist": 7.5, "face": 0.0, "time": 19.5, "day": 43, "lanterns": true},
	"ui_store": {"panel": ["open_store", ["store"]]},
	"ui_bakery": {"panel": ["open_store", ["bakery"]]},
	"ui_craft": {"panel": ["open_craft", ["kitchen"]]},
	"ui_bag": {"panel": ["open_bag", []]},
	"ui_calendar": {"panel": ["open_calendar", []]},
	"ui_pause": {"ui": "open_pause"},
	"ui_records": {"ui": "open_minigame_records"},
	"ui_book": {"ui": "open_book"},
	"ui_book_col": {"ui": "open_book_col", "seed_collection": true},
	"ui_quests": {"ui": "open_quests"},
	"house_genkan": {"house": Vector3(5.0, 0.0, 3.6), "pitch": 50.0, "dist": 9.2, "face": 180.0},
	"house_living": {"house": Vector3(2.2, 0.0, 0.1), "pitch": 50.0, "dist": 9.2, "face": 180.0},
	"house_kitchen": {"house": Vector3(-3.2, 0.0, 3.5), "pitch": 50.0, "dist": 9.2, "face": 90.0},
	"house_bedroom": {"house": Vector3(-3.6, 0.0, -0.4), "pitch": 50.0, "dist": 9.2, "face": 180.0},
	"arrive_farm": {"farm": true, "player": Vector3(-24.6, 0.1, 0.4), "yaw": -90.0, "pitch": 30.0, "dist": 7.5, "face": 90.0, "time": 10.0},
	"arrive_farm_back": {"farm": true, "player": Vector3(-24.6, 0.1, 0.4), "yaw": 90.0, "pitch": 22.0, "dist": 7.5, "face": -90.0, "time": 10.0},
	"arrive_town": {"player": Vector3(41.3, 0.1, -11.0), "yaw": 90.0, "pitch": 24.0, "dist": 7.0, "face": -90.0, "time": 10.0},
	"arrive_town_back": {"player": Vector3(38.0, 0.1, -11.0), "yaw": -90.0, "pitch": 18.0, "dist": 7.5, "face": 90.0, "time": 10.0},
	"lane_town_low": {"player": Vector3(42.2, 0.1, -11.0), "yaw": -90.0, "pitch": 14.0, "dist": 5.0, "face": 90.0, "time": 11.0},
	"lane_farm_low": {"farm": true, "player": Vector3(-27.4, 0.1, 0.4), "yaw": 90.0, "pitch": 12.0, "dist": 5.0, "face": -90.0, "time": 11.0},
	"board_close": {"player": Vector3(-8.1, 0.1, -7.7), "yaw": 160.0, "pitch": 18.0, "dist": 5.5, "face": 0.0, "time": 11.0},
	"market_walk": {"player": Vector3(-3.0, 0.1, 11.0), "yaw": 150.0, "pitch": 26.0, "dist": 7.0, "face": 0.0, "time": 10.2, "phase": "market"},
	"top_court_market": {"player": Vector3(2.0, 0.1, 9.0), "yaw": 180.0, "pitch": 88.0, "dist": 30.0, "face": 0.0, "time": 16.5, "phase": "market"},
	"top_court_natsu": {"player": Vector3(2.0, 0.1, 9.0), "yaw": 180.0, "pitch": 88.0, "dist": 30.0, "face": 0.0, "time": 19.0, "day": 17},
	"top_court_tanabata": {"player": Vector3(0.0, 0.1, 2.0), "yaw": 180.0, "pitch": 88.0, "dist": 26.0, "face": 0.0, "time": 18.0, "day": 4},
	"top_farm_river": {"farm": true, "player": Vector3(2.0, 0.1, 13.0), "yaw": 180.0, "pitch": 88.0, "dist": 26.0, "face": 0.0, "time": 19.8, "day": 24},
	"top_board": {"player": Vector3(-8.5, 0.1, -8.6), "yaw": 180.0, "pitch": 88.0, "dist": 9.0, "face": 0.0, "time": 11.0},
	"truck_town": {"player": Vector3(30.0, 0.1, -10.0), "yaw": -70.0, "pitch": 22.0, "dist": 7.0, "face": 90.0, "time": 11.0},
	"truck_farm": {"farm": true, "player": Vector3(-14.0, 0.1, 0.4), "yaw": -60.0, "pitch": 22.0, "dist": 7.5, "face": 90.0, "time": 11.0},
	"house_chest": {"house": Vector3(1.35, 0.0, 2.6), "pitch": 40.0, "dist": 5.0, "face": 0.0},
	"well_farm": {"farm": true, "player": Vector3(-13.0, 0.1, 4.0), "yaw": -40.0, "pitch": 20.0, "dist": 6.0, "face": -120.0, "time": 11.0},
	"well_top": {"farm": true, "player": Vector3(-15.5, 0.1, 9.2), "yaw": 180.0, "pitch": 88.0, "dist": 9.0, "face": 0.0, "time": 11.0},
	"bakery_front": {"interior": "bakery", "at": Vector3(0.0, 0.05, 2.2), "face": 180.0, "pitch": 24.0, "dist": 5.5, "time": 11.0},
	"bakery_left": {"interior": "bakery", "at": Vector3(-1.2, 0.05, 1.6), "face": 180.0, "pitch": 28.0, "dist": 4.5, "time": 11.0},
	"bakery_top": {"interior": "bakery", "at": Vector3(0.0, 0.05, 0.0), "face": 180.0, "pitch": 88.0, "dist": 11.0, "time": 11.0},
	"well_n": {"farm": true, "player": Vector3(-15.5, 0.1, 3.4), "yaw": 180.0, "pitch": 16.0, "dist": 5.5, "face": 0.0, "time": 11.0},
	"well_s": {"farm": true, "player": Vector3(-15.5, 0.1, 10.2), "yaw": 0.0, "pitch": 16.0, "dist": 5.5, "face": 180.0, "time": 11.0},
	"say_sora_neutral": {"say": "sora", "mood": "neutral", "player": Vector3(-6.0, 0.1, -11.0), "yaw": 180.0, "pitch": 20.0, "dist": 7.0, "face": 0.0, "time": 11.0},
	"say_sora_happy": {"say": "sora", "mood": "happy", "player": Vector3(-6.0, 0.1, -11.0), "yaw": 180.0, "pitch": 20.0, "dist": 7.0, "face": 0.0, "time": 11.0},
	"say_mio_neutral": {"say": "mio", "mood": "neutral", "player": Vector3(-6.0, 0.1, -11.0), "yaw": 180.0, "pitch": 20.0, "dist": 7.0, "face": 0.0, "time": 11.0},
	"say_mio_happy": {"say": "mio", "mood": "happy", "player": Vector3(-6.0, 0.1, -11.0), "yaw": 180.0, "pitch": 20.0, "dist": 7.0, "face": 0.0, "time": 11.0},
	"say_ren_neutral": {"say": "ren", "mood": "neutral", "player": Vector3(-6.0, 0.1, -11.0), "yaw": 180.0, "pitch": 20.0, "dist": 7.0, "face": 0.0, "time": 11.0},
	"say_ren_happy": {"say": "ren", "mood": "happy", "player": Vector3(-6.0, 0.1, -11.0), "yaw": 180.0, "pitch": 20.0, "dist": 7.0, "face": 0.0, "time": 11.0},
	"say_aoi_neutral": {"say": "aoi", "mood": "neutral", "player": Vector3(-6.0, 0.1, -11.0), "yaw": 180.0, "pitch": 20.0, "dist": 7.0, "face": 0.0, "time": 11.0},
	"say_aoi_happy": {"say": "aoi", "mood": "happy", "player": Vector3(-6.0, 0.1, -11.0), "yaw": 180.0, "pitch": 20.0, "dist": 7.0, "face": 0.0, "time": 11.0},
	"say_kazuko_neutral": {"say": "kazuko", "mood": "neutral", "player": Vector3(-6.0, 0.1, -11.0), "yaw": 180.0, "pitch": 20.0, "dist": 7.0, "face": 0.0, "time": 11.0},
	"say_kazuko_happy": {"say": "kazuko", "mood": "happy", "player": Vector3(-6.0, 0.1, -11.0), "yaw": 180.0, "pitch": 20.0, "dist": 7.0, "face": 0.0, "time": 11.0},
	"say_haru_neutral": {"say": "haru", "mood": "neutral", "player": Vector3(-6.0, 0.1, -11.0), "yaw": 180.0, "pitch": 20.0, "dist": 7.0, "face": 0.0, "time": 11.0},
	"say_haru_happy": {"say": "haru", "mood": "happy", "player": Vector3(-6.0, 0.1, -11.0), "yaw": 180.0, "pitch": 20.0, "dist": 7.0, "face": 0.0, "time": 11.0},
	"say_tanaka_neutral": {"say": "tanaka", "mood": "neutral", "player": Vector3(-6.0, 0.1, -11.0), "yaw": 180.0, "pitch": 20.0, "dist": 7.0, "face": 0.0, "time": 11.0},
	"say_tanaka_happy": {"say": "tanaka", "mood": "happy", "player": Vector3(-6.0, 0.1, -11.0), "yaw": 180.0, "pitch": 20.0, "dist": 7.0, "face": 0.0, "time": 11.0},
	"lane_town_high": {"player": Vector3(30.0, 0.1, -11.0), "yaw": -90.0, "pitch": 28.0, "dist": 14.0, "face": 90.0, "time": 16.0},
	"lane_farm_high": {"farm": true, "player": Vector3(-20.0, 0.1, 0.4), "yaw": 90.0, "pitch": 20.0, "dist": 12.0, "face": -90.0, "time": 16.0},
	"workroom_table": {"interior": "workroom", "at": Vector3(-2.6, .05, .9), "face": 180.0, "pitch": 24.0, "dist": 4.5, "time": 10.5},
	"workroom_overview": {"interior": "workroom", "at": Vector3(0, .05, 2.6), "face": 180.0, "pitch": 46.0, "dist": 9.4, "time": 10.5},
	"store_in": {"interior": "store", "at": Vector3(0.6, 0.05, 1.9), "face": 200.0, "pitch": 46.0, "dist": 8.6, "time": 11.0},
	"store_close": {"interior": "store", "at": Vector3(-1.6, 0.05, 1.5), "face": -90.0, "pitch": 30.0, "dist": 4.8, "time": 11.0},
	"bakery_in": {"interior": "bakery", "at": Vector3(0.0, 0.05, 2.0), "face": 180.0, "pitch": 46.0, "dist": 8.6, "time": 9.0},
	"bakery_close": {"interior": "bakery", "at": Vector3(-1.9, 0.05, 0.0), "face": -90.0, "pitch": 26.0, "dist": 4.6, "time": 9.0},
	"house_engawa": {"house": Vector3(1.6, 0.0, -3.9), "pitch": 46.0, "dist": 9.5, "face": 180.0},
	"house_wide": {"house": Vector3(0.0, 0.0, 0.8), "pitch": 56.0, "dist": 10.0, "face": 180.0},
	"house_evening": {"house": Vector3(2.2, 0.0, 0.1), "pitch": 50.0, "dist": 9.2, "face": 180.0, "phase": "market"},
	# facades, looked at from across the street and at an angle (depth of windows, eaves, doors)
	"facade_store": {"player": Vector3(-36.0, 0.1, -9.6), "yaw": 20.0, "pitch": 8.0, "dist": 9.0, "face": 180.0, "time": 10.5},
	"facade_bakery": {"player": Vector3(-24.0, 0.1, -9.6), "yaw": -20.0, "pitch": 8.0, "dist": 9.0, "face": 180.0, "time": 10.5},
	"facade_florist": {"player": Vector3(-12.0, 0.1, -9.6), "yaw": 25.0, "pitch": 8.0, "dist": 9.0, "face": 180.0, "time": 10.5},
	"facade_zakka": {"player": Vector3(0.0, 0.1, -9.6), "yaw": -25.0, "pitch": 8.0, "dist": 9.0, "face": 180.0, "time": 10.5},
	"facade_post": {"player": Vector3(12.5, 0.1, -9.6), "yaw": 25.0, "pitch": 8.0, "dist": 9.0, "face": 180.0, "time": 10.5},
	"facade_apart": {"player": Vector3(25.5, 0.1, -9.6), "yaw": -25.0, "pitch": 8.0, "dist": 9.0, "face": 180.0, "time": 10.5},
	"facade_east": {"player": Vector3(35.5, 0.1, -9.6), "yaw": 20.0, "pitch": 8.0, "dist": 9.0, "face": 180.0, "time": 10.5},
	"facade_south": {"player": Vector3(-30.0, 0.1, -11.5), "yaw": 160.0, "pitch": 8.0, "dist": 9.0, "face": 0.0, "time": 10.5},
	"facade_lane": {"player": Vector3(19.4, 0.1, 9.0), "yaw": -120.0, "pitch": 10.0, "dist": 8.0, "face": 90.0, "time": 10.5},
	"facade_lane_s": {"player": Vector3(19.4, 0.1, 21.0), "yaw": -60.0, "pitch": 10.0, "dist": 8.0, "face": 90.0, "time": 10.5},
	"close_store": {"player": Vector3(-33.0, 0.1, -13.2), "yaw": 60.0, "pitch": 6.0, "dist": 5.0, "face": 180.0, "time": 10.5},
	"win_store": {"player": Vector3(-35.6, 0.1, -11.0), "yaw": 0.0, "pitch": 4.0, "dist": 4.0, "face": 180.0, "time": 10.5},
	"win_florist": {"player": Vector3(-12.0, 0.1, -11.0), "yaw": 0.0, "pitch": 4.0, "dist": 4.0, "face": 180.0, "time": 10.5},
	"win_night": {"player": Vector3(-24.0, 0.1, -10.5), "yaw": 15.0, "pitch": 6.0, "dist": 9.0, "face": 180.0, "time": 20.8},
	"close_bakery": {"player": Vector3(-21.0, 0.1, -13.2), "yaw": 60.0, "pitch": 6.0, "dist": 5.0, "face": 180.0, "time": 10.5},
	"close_florist": {"player": Vector3(-9.0, 0.1, -13.2), "yaw": 60.0, "pitch": 6.0, "dist": 5.0, "face": 180.0, "time": 10.5},
	"close_zakka": {"player": Vector3(3.0, 0.1, -13.2), "yaw": 60.0, "pitch": 6.0, "dist": 5.0, "face": 180.0, "time": 10.5},
	"close_post": {"player": Vector3(15.5, 0.1, -13.2), "yaw": 60.0, "pitch": 6.0, "dist": 5.0, "face": 180.0, "time": 10.5},
	"close_apart": {"player": Vector3(28.5, 0.1, -13.2), "yaw": 60.0, "pitch": 6.0, "dist": 5.0, "face": 180.0, "time": 10.5},
	"close_south": {"player": Vector3(-32.0, 0.1, -7.0), "yaw": 120.0, "pitch": 6.0, "dist": 5.0, "face": 0.0, "time": 10.5},
	"close_center": {"player": Vector3(-20.0, 0.1, -7.0), "yaw": 120.0, "pitch": 6.0, "dist": 5.0, "face": 0.0, "time": 10.5},
	"close_home": {"player": Vector3(20.5, 0.1, 2.5), "yaw": -40.0, "pitch": 6.0, "dist": 5.0, "face": 90.0, "time": 10.5},
	# grazing angle down the row: reveals whether buildings have real depth or are thin shells
	"row_graze_n": {"player": Vector3(-46.0, 0.1, -13.0), "yaw": -78.0, "pitch": 4.0, "dist": 3.0, "face": 90.0, "time": 10.5},
	"row_graze_n2": {"player": Vector3(20.0, 0.1, -13.0), "yaw": -78.0, "pitch": 4.0, "dist": 3.0, "face": 90.0, "time": 10.5},
	"row_graze_s": {"player": Vector3(-46.0, 0.1, -8.0), "yaw": 78.0, "pitch": 4.0, "dist": 3.0, "face": 90.0, "time": 10.5},
	"side_south": {"player": Vector3(-40.0, 0.1, -1.5), "yaw": 0.0, "pitch": 4.0, "dist": 6.0, "face": 90.0, "time": 10.5},
	"side_center": {"player": Vector3(-27.0, 0.1, -1.5), "yaw": 0.0, "pitch": 4.0, "dist": 6.0, "face": 90.0, "time": 10.5},
	"back_south": {"player": Vector3(-35.0, 0.1, 4.0), "yaw": 180.0, "pitch": 4.0, "dist": 7.0, "face": 0.0, "time": 10.5},
	"back_center": {"player": Vector3(-23.0, 0.1, 4.0), "yaw": 180.0, "pitch": 4.0, "dist": 7.0, "face": 0.0, "time": 10.5},
	# right up against the back wall, from inside the walkable garden strip: roofs must not loom over it
	"back_south_near": {"player": Vector3(-35.0, 0.1, 1.0), "yaw": 180.0, "pitch": 4.0, "dist": 3.0, "face": 0.0, "time": 10.5},
	"back_center_near": {"player": Vector3(-23.0, 0.1, 1.0), "yaw": 180.0, "pitch": 4.0, "dist": 3.0, "face": 0.0, "time": 10.5},
	# what lies beyond the walls: the backdrop has to read as a real town, not painted flats
	"beyond_south": {"player": Vector3(2.0, 0.1, 18.0), "yaw": 180.0, "pitch": 6.0, "dist": 9.0, "face": 180.0, "time": 10.5},
	"beyond_north": {"player": Vector3(-6.0, 0.1, -6.8), "yaw": 0.0, "pitch": 4.0, "dist": 9.0, "face": 0.0, "time": 10.5},
	"beyond_west": {"player": Vector3(-40.0, 0.1, -10.0), "yaw": 90.0, "pitch": 6.0, "dist": 9.0, "face": -90.0, "time": 10.5},
	"beyond_east": {"player": Vector3(12.0, 0.1, 10.0), "yaw": -90.0, "pitch": 6.0, "dist": 9.0, "face": 90.0, "time": 10.5},
	"beyond_lane": {"player": Vector3(19.7, 0.1, 22.0), "yaw": 180.0, "pitch": 6.0, "dist": 8.0, "face": 180.0, "time": 10.5},
	"beyond_farm": {"farm": true, "player": Vector3(0.0, 0.1, 24.0), "yaw": 180.0, "pitch": 8.0, "dist": 9.0, "face": 180.0, "time": 10.5},
}
var main: Node


func _ready() -> void:
	main = get_parent()
	await _run()


func _arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.split("=", true, 1)[1]
	return def


func _run() -> void:
	var dir := _arg("shots", "user://shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var names := _arg("views", ",".join(VIEWS.keys())).split(",")
	# --clean=1 hides the HUD (quest board, coins, weather badge, hint bar, toasts)
	# for marketing/site screenshots that should show only the game world.
	var wallpaper:=OS.get_cmdline_user_args().has("--wallpaper")
	var clean := _arg("clean", "") == "1"
	for i in 30:
		await get_tree().process_frame
	for n in names:
		if not VIEWS.has(n):
			continue
		var v: Dictionary = VIEWS[n]
		if v.get("place_fixture",false):
			GameState.placements=[{"uid":990,"item":"bunting","x":5.5,"z":11.2,"rot":0},{"uid":991,"item":"lantern","x":9.5,"z":12.4,"rot":0}]
			main.placement.rebuild()
		main.rig.cam.transform = Transform3D.IDENTITY
		main.rig.process_mode = Node.PROCESS_MODE_INHERIT
		main.player.visible = true
		GameState.clock_paused = true
		if v.has("bakery_fixture"):
			GameState.quests["Q16"] = {"state": "active", "step": 5 if n == "bakery_market" else 4}
			GameState.tracked_quest = "Q16"
			for qid in ["Q00", "Q05", "Q06"]:
				GameState.quests[qid] = {"state": "done", "step": GameState.quests_db[qid].steps.size()}
			GameState.flags["bakery_menu"] = int(v.bakery_fixture)
			GameState.flags["bakery_due_day"] = 10
			GameState.flags["bakery_order_active"] = n != "bakery_market"
			GameState.flags["bakery_first_served"] = n == "bakery_market"
			GameState.flags["bakery_served_day"] = 10
			GameState.add_item("tomato", 2, true)
			GameState.add_item("cucumber", 1, true)
			GameState.state_changed.emit()
			main.ui.toast_box.visible = false
			main.ui.panels.set_cards_visible(false)
		if v.get("demo", false):
			_demo_farm()
		if v.has("day"):
			GameState.day = int(v.day)
			main.world.sync_festivals()
			main._last_fest = ""
		GameState.minute = float(v.get("time", 10.0)) * 60.0
		GameState.weather = str(v.get("weather", "sunny"))
		main.world.update_time(GameState.minute, GameState.weather, true)
		main.update_npcs(true)
		main.ui.refresh_hud()
		main.ui.set_hud_visible(not clean)
		main.ui.panels.set_cards_visible(not clean and not v.has("bakery_fixture"))
		for id in main.npcs:
			var tag := (main.npcs[id] as NPC).tag
			if tag:
				tag.visible = not clean
		if v.has("panel"):
			main.ui.panels.callv(v.panel[0], v.panel[1])
			for i in 20:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, n])
			print("SHOT ", n)
			main.ui.close_modal()
			for i in 5:
				await get_tree().process_frame
			continue
		if v.has("ui"):
			if v.get("seed_collection", false):
				for c in Progress.col_db:
					Progress.find(c.id)
			main.ui.call(v.ui)
			for i in 20:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, n])
			print("SHOT ", n)
			main.ui.close_modal()
			for i in 5:
				await get_tree().process_frame
			continue
		if v.has("phase") and GameState.phase != v.phase:
			GameState.phase = v.phase
			main.world.apply_phase(v.phase, false)
		if v.has("interior"):
			main.world.set_region("town")
			main.in_room = false
			await main.enter_interior(str(v.interior))
			main.player.global_position = InteriorBuilder.spec_for(str(v.interior)).origin + v.get("at", Vector3(0, 0.05, 1.8))
			main.player.set_facing(deg_to_rad(v.get("face", 180.0)))
			main.rig.pitch = v.get("pitch", 46.0)
			main.rig.dist = v.get("dist", 8.6)
			main.rig.snap()
			main.update_npcs(true)
			if str(v.interior) == "bakery":
				var sp := InteriorBuilder.spec_for("bakery")
				main.npcs.ren.place(sp.origin + sp.keeper, sp.keeper_yaw)
			if v.has("inside_camera"):
				main.player.visible=false;main.rig.process_mode=Node.PROCESS_MODE_DISABLED
				main.rig.cam.global_position=InteriorBuilder.spec_for(str(v.interior)).origin+v.inside_camera
				main.rig.cam.look_at(InteriorBuilder.spec_for(str(v.interior)).origin+v.inside_focus)
				main.shop_life._caption_left=0.0
			for i in 40:
				await get_tree().process_frame
			if v.has("tv_signal"):
				main.shop_life.elapsed=float(v.tv_signal);main.shop_life.tick(0.0)
				await get_tree().process_frame
				await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, n])
			print("SHOT ", n)
			main.in_room = false
			main.room_kind = ""
			continue
		if v.has("say"):
			# the dialogue box over the street, to check a portrait in the real UI
			main.ui.instant = true
			main.ui.dialogue_begin()
			await main.ui.say(str(v.say), str(v.get("mood", "neutral")), "（头像检查）这是一句用来看头像边缘的台词。")
			for i in 20:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, n])
			main.ui.dialogue_end()
			main.ui.instant = false
			print("SHOT ", n)
			continue
		if v.has("house"):
			main._put_in_room(HouseBuilder.ORIGIN + v.house + Vector3(0, 0.05, 0))
			main.player.set_facing(deg_to_rad(v.face))
			main.rig.pitch = v.pitch
			main.rig.dist = v.dist
			main.rig.snap()
			for i in 40:
				await get_tree().process_frame
			var im := get_viewport().get_texture().get_image()
			im.save_png("%s/%s.png" % [dir, n])
			print("SHOT ", n)
			continue
		if main.in_room:
			main.in_room = false
			GameState.player_in_room = false
			main.world.set_indoor_look(false)
			main.rig.fixed = false
			main.rig.collide = true
		main.world.set_region("farm" if v.get("farm", false) else "town")
		main.player.global_position = (FarmBuilder.ORIGIN if v.get("farm", false) else Vector3.ZERO) + v.player
		main.player.set_facing(deg_to_rad(float(v.get("face", 180.0))))
		main.rig.yaw = float(v.get("yaw", 0.0))
		main.rig.pitch = float(v.get("pitch", 20.0))
		main.rig.dist = float(v.get("dist", 8.0))
		main.rig.snap()
		main.weather_fx.set_weather(GameState.weather, false)
		main.update_npcs(true)
		main.sync_festival_state()
		main.world.farm.fx.fireworks_on = v.get("fireworks", false)
		main.world.farm.fx.rate = 3.0
		main.world.farm.fx.lanterns_on = v.get("lanterns", false)
		if v.get("lanterns", false):
			for i in 10:
				main.world.farm.fx.float_lantern(false, Vector3(-20.0 + i * 4.0, 0, 15.5 + (i % 3) * 1.2))
		if v.has("gesture"):
			# line the neighbours up facing the camera and freeze them at the gesture's peak
			var ids: Array = main.npcs.keys()
			var with_player: bool=bool(v.get("include_player",false))
			for i in ids.size():
				var np: NPC = main.npcs[ids[i]]
				np.visible = true
				np.fest_key = "shots"
				np.place(v.player + Vector3(-4.2 + (i+1)*1.4 if with_player else -3.6+i*1.2, 0.0, -1.0), 0.0)
			await get_tree().process_frame
			for id in ids:
				var np: NPC = main.npcs[id]
				if np.anim.has(str(v.gesture)):
					np.anim.ap.play(str(v.gesture), 0.0)
					np.anim.ap.seek(np.anim.ap.current_animation_length * float(v.get("at_t", 0.45)), true)
					np.process_mode = Node.PROCESS_MODE_DISABLED
			main.player.visible = with_player
			if with_player:
				main.player.global_position=v.player+Vector3(-4.2,0,-1)
				main.player.set_facing(0.0)
				var player_anim: CharAnim=main.player.anim
				player_anim.ap.play(str(v.gesture),0.0)
				player_anim.ap.seek(player_anim.ap.current_animation_length*float(v.get("at_t",.45)),true)
				main.player.process_mode=Node.PROCESS_MODE_DISABLED
		if v.has("camera_at"):
			main.player.visible = bool(v.get("actors",false))
			main.rig.process_mode = Node.PROCESS_MODE_DISABLED
			var camera_origin: Vector3 = FarmBuilder.ORIGIN if v.get("farm", false) else Vector3.ZERO
			main.rig.cam.global_position = camera_origin + v.camera_at
			main.rig.cam.look_at(camera_origin + v.camera_focus)
			if v.get("sun_view",false):
				main.rig.cam.look_at(main.rig.cam.global_position+main.world.sun.global_basis.z*100.0)
		if v.has("settle_seconds"):
			await get_tree().create_timer(float(v.settle_seconds)).timeout
		for i in (80 if v.get("fireworks", false) else 25):
			await get_tree().process_frame
		if wallpaper:
			main.photo.toggle();await main.photo.save_picture()
			if main.photo.last_path!="":DirAccess.copy_absolute(main.photo.last_path,"%s/%s_4k.png"%[dir,n])
			main.photo.finish()
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [dir, n])
		print("SHOT ", n)
	get_tree().quit()


## A lived-in allotment for screenshots: every stage and crop somewhere.
func _demo_farm() -> void:
	var G := GameState
	if G.flags.get("_demo", false):
		return
	G.flags["_demo"] = true
	G.open_plots(G.plot_ids(), true)
	var spec := {
		"farm0": ["tomato", 4, true], "farm1": ["cucumber", 3, false], "farm2": ["radish", 1, true], "farm3": ["komatsuna", 2, false],
		"farm4": ["sunflower", 5, true], "farm5": ["edamame", 2, false], "farm6": ["radish", 3, false], "farm7": ["tomato", 2, true],
		"farm8": ["", 0, false], "farm9": ["komatsuna", 0, true], "farm10": ["sunflower", 3, false], "farm11": ["cucumber", 1, true],
		"gh0": ["strawberry", 5, true], "gh1": ["strawberry", 2, false],
		"yard0": ["tomato", 4, true], "yard1": ["komatsuna", 1, true], "yard2": ["radish", 3, false], "yard3": ["", 0, false],
		"court": ["sunflower", 5, true],
	}
	for id in spec:
		var p: Dictionary = G.plots[id]
		p.crop = spec[id][0]
		p.days = spec[id][1]
		p.water = spec[id][2]
	G.plots.farm8.tilled = false
	G.flags["court_plot"] = true
	G.plots_changed.emit()
	G.farm_xp = 400
	G.coins = 860
	for iid in ["tomato", "cucumber", "carrot", "potato", "flour", "egg", "salad", "focaccia", "seed_carrot", "seed_corn"]:
		G.add_item(iid, 4, true)
	G.add_item("hoe", 1, true)
	G.add_item("farm_can", 1, true)
	for id in ["tanaka", "aoi"]:
		G.flags["met_" + id] = true
	G.day = 2
