extends SceneTree
func _initialize():
 var im = Image.load_from_file("res://assets/sprites/characters/generated/pawn_simple.png")
 var result = []
 for row in range(2):
  for col in range(4):
   var left = im.get_width()
   var top = im.get_height()
   var right = 0
   var bottom = 0
   for y in range(0 if row == 0 else 535,535 if row == 0 else im.get_height()):
    for x in range(col*im.get_width()/4,(col+1)*im.get_width()/4):
     if im.get_pixel(x,y).a > 0.5:
      left=mini(left,x)
      top=mini(top,y)
      right=maxi(right,x)
      bottom=maxi(bottom,y)
   result.append([left,top,right-left+1,bottom-top+1])
 print(result)
 var f=FileAccess.open("res://assets/sprites/characters/generated/pawn_regions.json",FileAccess.WRITE)
 f.store_string(JSON.stringify(result))
 quit()

