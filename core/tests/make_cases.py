# Generates tests/cases.json: words as they appear on screen + the layout they were typed in.
import json
fix_en = "ghbdtn vbh [dfnftn GeynjCdbnxth? cjplflbv cdjq Jxtym yt yfv ntcn rjvgm.nth ghjuhfvvf rfr ltkf? Ghbdtn ntrcn hf,jnf vfibyt ;tkfntkmyj rjvfyljq Irfa ds,hfnm cltkfnm Vjcrdf".split()
fix_ru = "руддщ цщкдв ыщагтв пщщв еуые црфе ещ шы ьщтлун Ыьфкегь ыцшеср црфеы".split()
keep_en = ("Grok SketchUp OpenCore ydotool gsettings Wayland punto smartum elementary Bitrix Amnezia github wifi online google linux "
           "hello world the and google.com don't vs a I ok iPad macOS hte teh recieve adress Ubuntu Chrome Telegram WhatsApp Avito Yandex "
           "Wildberries Ozon youtube instagram Bluetooth Netcraze Hopper Apacer Samsung Tornado Moskovskaya Alushta Maria Krym Simferopol "
           "Sevastopol Yalta Feodosia vk okay lol btw thx pls asap ETA CRM API USB HDMI SSD NVMe Basis Bazis Codex ChatGPT Musk Ivan").split()
keep_ru = ("Битрикс смартум Олег Тарханкут Алушта Ленинградская ютуб гугл линукс коннектор замер привет мир шт я в и не кухня шкаф "
           "Мастер-Крым привте сдлеать щас чё ваще спс пжлст норм ок Симферополь Севастополь Ялта Феодосия Саки Евпатория Иваненко "
           "КрымАкрил Дельфин Мария Иван Петров Маск ЛДСП МДФ фасад столешница кромка распил присадка Блюм Хеттих Базис СкетчАп ВК ИП ООО КП ТЗ").split()
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "python"))
from smartum_core import retype
cases = []
for w in fix_en: cases.append({"shown": w, "layout": "en", "fix": True, "result": retype(w, "en")})
for w in fix_ru: cases.append({"shown": w, "layout": "ru", "fix": True, "result": retype(w, "ru")})
for w in keep_en: cases.append({"shown": w, "layout": "en", "fix": False})
for w in keep_ru: cases.append({"shown": w, "layout": "ru", "fix": False})
json.dump(cases, open(os.path.join(os.path.dirname(__file__), "cases.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=0)
print(len(cases), "cases")
