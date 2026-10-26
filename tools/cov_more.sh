#!/bin/sh
# Сценарии добора покрытия (24.10.2026): запускаются параллельно, трассы — build/cov/cov_<имя>.txt
cd "$(dirname "$0")/.."
BP0='bpset df76,1,{b@af0b=0;b@af20=18;b@af21=18;b@af1e=a;b@af1f=e2;g}'
# подзарядка: клетка 6 палубы 0 (столбец 8, ряд 3), энергия 0x10
QZ_DBG='bpset df76,1,{b@af0b=0;b@af20=88;b@af21=38;b@af1e=26;b@af1f=ea;g}' QZ_POKE="af93=10@1000-1000" QZ_MOVES="900:" \
  sh tools/cov_scen.sh recharge 2500 &
# гибель: класс 1 -> новый слабый дроид, вторая гибель -> конец игры, v_score_add 5000 (досчитывается в конце игры) > рекорда 3000 -> ввод имени
QZ_POKE="af89=11@1490-1490,af93=0@1500-1500,b05a=88@2590-2590,b05b=13@2590-2590,af93=0@2600-2600" QZ_RANDOM=5 QZ_SHOT=200 \
  sh tools/cov_scen.sh death 6000 &
# город: перед каждым dec счётчика палубы (D97B) — 1 на палубе 0, 0 на прочих -> убийство очищает палубу и город
QZ_DBG="$BP0;;bpset d97b,1,{b@8078=1;b@8079=0;b@807a=0;b@807b=0;b@807c=0;b@807d=0;b@807e=0;b@807f=0;g}" QZ_RANDOM=12 \
  sh tools/cov_scen.sh cityclear 6000 &
# вспышка: оружие игрока 5 (DISRUPTOR)
QZ_POKE="af88=05@900-6000" QZ_RANDOM=9 sh tools/cov_scen.sh flash 6000 &
# отладочный монитор (v_mon_on = 1) + клавиши
QZ_POKE="b423=1@900-1900" QZ_MOVES="900:" QZ_KEYS="1000:LINE4:8,1050:LINE4:8,1100:LINE4:7,1150:LINE4:6,1200:LINE3:5,1250:LINE4:8,1300:LINE4:8,1350:LINE4:8,1400:LINE4:7,1450:LINE4:6,1500:LINE4:8,1550:LINE4:8,1600:LINE4:7,1650:LINE4:6,1700:LINE3:5" \
  sh tools/cov_scen.sh monitor 2000 &
# клавиатура: смена режима панели (W), лифт на ту же палубу
QZ_CTRL=1 QZ_DBG="$BP0" QZ_MOVES="900:" QZ_KEYS="700:LINE6:ENTER,1000:LINE2:w,1200:LINE2:w,1400:LINE6:ENTER,1600:LINE6:ENTER" \
  sh tools/cov_scen.sh kbd2 2500 &
wait
# вспышка от дроида: перед проверкой оружия (D6EF) у объекта оружие 5
QZ_DBG='bpset d6ef,1,{b@af83=(b@af83&f0)|5;g}' QZ_RANDOM=21 sh tools/cov_scen.sh enflash 5000 &
# пустая палуба: население палубы 0 — сразу конец списка (FF) при входе
QZ_DBG='bpset df76,1,{b@af0b=0;b@af20=18;b@af21=18;b@af1e=a;b@af1f=e2;b@a1b0=ff;g}' QZ_MOVES="900:" \
  sh tools/cov_scen.sh emptydeck 1500 &
# лифт на ту же палубу: вход удержанием огня, выход огнём без выбора
QZ_DBG="$BP0" QZ_MOVES="900:,950:Fire,1000:,1300:Fire,1306:" QZ_SHOT=100 sh tools/cov_scen.sh liftsame 1800 &
# подзарядка с энергией 4 (предупреждение и снятие его)
QZ_DBG='bpset df76,1,{b@af0b=0;b@af20=88;b@af21=38;b@af1e=26;b@af1f=ea;g}' QZ_POKE="af93=4@1000-1000" QZ_MOVES="900:" \
  sh tools/cov_scen.sh recharge2 2500 &
wait
# длинные случайные игры
for s in 31 32 33 34 35 36; do sh tools/cov_run.sh $s 20000 & done; wait
# ---- пакет 2 ----
CONS='bpset df76,1,{b@af0b=0;b@af20=a8;b@af21=58;b@af1e=2e;b@af1f=f2;g}'
# база дроидов до конца: класс игрока 7, листание вниз по всем типам
QZ_DBG="$CONS" QZ_POKE="af89=07@900-6000" QZ_MOVES="1000:Fire,1100:,1300:Right,1308:,1310:Right,1318:,1320:Right,1328:,1400:Fire,1406:,1500:Down,1508:,1600:Down,1608:,1700:Down,1708:,1800:Down,1808:,1900:Down,1908:,2000:Down,2008:,2100:Down,2108:,2200:Down,2208:,2300:Down,2308:,2400:Down,2408:,2500:Down,2508:,2600:Down,2608:,2700:Down,2708:,2800:Down,2808:,2900:Down,2908:,3000:Down,3008:,3100:Down,3108:,3200:Down,3208:,3300:Down,3308:,3400:Down,3408:,3500:Down,3508:,3600:Down,3608:,3700:Down,3708:,3800:Down,3808:,3900:Down,3908:,4000:Down,4008:,4100:Down,4108:,4200:Down,4208:,4300:Down,4308:,4400:Down,4408:,4500:Down,4508:,4600:Down,4608:,4700:Down,4708:,4800:Down,4808:,4900:Fire,4906:" \
  QZ_SHOT=500 sh tools/cov_scen.sh cons_all 5200 &
# трофеи: перевес 8 (всё доступно), выбор строк по кругу 1..5, 0 — выход; LASER SHIELDS у игрока
QZ_DBG='bpset cb21,1,{b@afad=8;g};;bpset bc23,1,{b@bcfb=b@ff30%6;b@ff30=b@ff30+1;g}' QZ_POKE="ff30=1@1-1,af68=1@900-12000,af8a=24@900-12000" QZ_RANDOM=12 \
  sh tools/cov_scen.sh salv_all 12000 &
# детектор и поездка в лифте
QZ_DBG="$BP0" QZ_POKE="af8a=81@900-3000" QZ_MOVES="900:,950:Fire,1000:,1200:Down,1206:,1500:Up,1506:,1800:Up,1806:,2100:Fire,2106:" \
  sh tools/cov_scen.sh lift_det 2500 &
# таран тяжёлым шасси с RAM THRUSTER, серия убийств у предела
QZ_POKE="af88=71@900-9000,af8a=16@900-9000,b005=fa@900-9000" QZ_RANDOM=13 sh tools/cov_scen.sh ram 9000 &
wait
# ---- пакет 3: редкие ветки точками останова ----
# таран лёгкого дроида (D798: масса противника 0), щит от лазера (D8A6), серия убийств у предела (D948),
# оглядывание (DB14: v_look = 1), предел импульсов противника (C91C: класс 7)
QZ_DBG='bpset d798,1,{b@af83=0;b@af88=71;g};;bpset d8a6,1,{b@af8a=24;g};;bpset d948,1,{b@b005=ff;g};;bpset db14,1,{b@af97=1;g};;bpset c91c,1,{b@af84=7;g}' \
  QZ_POKE="af68=1@900-9000" QZ_RANDOM=12 sh tools/cov_scen.sh rare 9000 &
for s in 13 31; do QZ_DBG='bpset d798,1,{b@af83=0;b@af88=71;g};;bpset d8a6,1,{b@af8a=24;g};;bpset d948,1,{b@b005=ff;g};;bpset db14,1,{b@af97=1;g}' QZ_RANDOM=$s sh tools/cov_scen.sh rare$s 12000 & done
wait
