class_name CharacterLook
extends Resource
## 一个可选角色的名片：皮肤键、叫什么、排第几。
##
## 角色清单是**扫 `characters/` 目录**得来的（见 `Catalog`）。
## **不扫皮肤包的目录**：包里混着 `backdrop`、`enemies`、`ui` 一堆非角色的文件夹，
## 而且默认包里一个角色目录都没有（占位方块不需要贴图），扫出来会是空的。

## 皮肤键：玩家的 `skin_key` 和存档里的 `look` 用的都是它，
## 素材包按它找外观场景（`SkinPack.appearances`）、贴图按它找目录。
@export var key := &""
## 界面上怎么称呼它。现在还没显示，留给以后的角色选择界面。
@export var display_name := ""
## 排第几：人物设置界面上三个头像从左到右的顺序。
@export var order := 0
