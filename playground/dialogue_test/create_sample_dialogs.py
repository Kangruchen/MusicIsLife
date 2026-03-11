"""Create a sample Excel file 'sample_dialogs.xlsx' for testing the converter.

This script uses openpyxl to write a sheet named '节奏游戏对话表' with the
expected headers and a few example rows (including empty artwork and next_id).
"""
from openpyxl import Workbook
from pathlib import Path

wb = Workbook()
ws = wb.active
ws.title = "节奏游戏对话表"

headers = [
    "对话ID",
    "角色类型",
    "角色名",
    "对话文本",
    "立绘资源路径",
    "下一条ID",
    "触发场景",
    "语音ID",
]
ws.append(headers)

# Example rows
rows = [
    [1, "NPC", "小明", "你好，欢迎来到节奏世界！", "res://assets/portraits/hero.png", 2, "StartScene", "voice_001"],
    [2, "PLAYER", "玩家", "让我们开始吧！", None, 3, "Level1", ""],
    [3, "NPC", "小明", "祝你好运！", "", None, "", "voice_003"],
]
for r in rows:
    ws.append(r)

out = Path(__file__).parent / "sample_dialogs.xlsx"
wb.save(str(out))
print(f"Sample Excel written to: {out}")
