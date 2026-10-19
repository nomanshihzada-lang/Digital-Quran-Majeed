require "import"
import "android.widget.*"
import "android.view.*"
import "android.app.*"
import "android.media.*"
import "android.content.*"
import "android.os.*"
import "android.graphics.Typeface"
import "android.graphics.Color"
import "android.net.Uri"
import "java.io.File"
import "java.io.FileOutputStream"
import "java.lang.Runnable"
import "java.lang.Thread"
import "java.net.URL"
import "java.net.URLEncoder"
import "java.io.BufferedReader"
import "java.io.InputStreamReader"
import "android.text.TextWatcher"
import "android.speech.RecognizerIntent"
import "java.util.Calendar"
import "java.util.TimeZone"
local mp = nil
local screen = "home"
local currentIndex = 1
local currentReciter = 1
local autoNextMode = true
local isPaused = false
local PS = {speed=1.0, ayahRepeat=1, surahRepeat=1, surahRepeatRem=0, externalPlayback=false, externalPreparing=false, externalPausePending=false, externalUrl=nil, externalPath=nil, externalLabel=nil, notifActionErrorShown=false}
V25 = V25 or { items = {}, files = {}, modes = {}, qariItems = {}, qariFiles = {} }
function savePlaybackSpeed(v)
PS.speed = v
pcall(function()
if activity then
activity.getSharedPreferences("QuranAppPrefs", 0).edit().putFloat("playbackSpeed", v).apply()
end
end)
end
function applyPlaybackSpeed(player)
if not player then return end
pcall(function()
if Build.VERSION.SDK_INT >= 23 then
player.setPlaybackParams(player.getPlaybackParams().setSpeed(PS.speed))
end
end)
end
local sleepTimerMinutes = 0
local seekSeconds = 10
local targetSleepTime = 0
local handler = Handler(Looper.getMainLooper())
local updateTask = nil
local publicDownloadsRoot = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS).getAbsolutePath()
local downloadDir = publicDownloadsRoot .. "/Quran_Files/"
if not File(downloadDir).exists() then File(downloadDir).mkdirs() end
local duaAudioDir = publicDownloadsRoot .. "/Dua_Audio/"
if not File(duaAudioDir).exists() then File(duaAudioDir).mkdirs() end
local bookAudioDir = publicDownloadsRoot .. "/Islam_Books/"
if not File(bookAudioDir).exists() then File(bookAudioDir).mkdirs() end
local paraAudioDir = publicDownloadsRoot .. "/Para_Audio/"
if not File(paraAudioDir).exists() then File(paraAudioDir).mkdirs() end
local azanAudioDir = publicDownloadsRoot .. "/Azan_Audio/"
if not File(azanAudioDir).exists() then File(azanAudioDir).mkdirs() end
local duaMp = nil
local appColorStr = "#1B5E20"
local M = {}
local BDIT = "Islamic Duain - Masnoon Duain (Audio)"
M.getThemeColors = function() return "#FFFFFF", "#000000" end
M.applyWallpaper = function(view, bgColor) if view then view.setBackgroundColor(Color.parseColor(bgColor)) end end
local function tr(text) return text end
pcall(function()
if activity == nil and this ~= nil then activity = this end
end)
local prefs = nil
pcall(function()
prefs = activity.getSharedPreferences("QuranAppPrefs", 0)
end)
if not prefs then
error("Activity context nahi mila.\n\nAndroLua Pro mein project bana kar Run karein.\nJieshuo → Tools folder se seedha main.lua load mat karein — wahan Activity inject nahi hoti.\n\nSahi tareeqa: AndroLua Pro → New Project → is file ko main.lua banao → Run.")
end
pcall(function()
local s = prefs.getFloat("playbackSpeed", 1.0)
if s and s > 0 then PS.speed = s end
end)
local completedSurahsStr = prefs.getString("completedSurahs", "")
local completedSurahs = {}
if completedSurahsStr ~= "" then for s in string.gmatch(completedSurahsStr, "([^,]+)") do completedSurahs[tonumber(s)] = true end end
M.saveCompletedSurahs = function()
local arr = {}
for k,v in pairs(completedSurahs) do if v then table.insert(arr, k) end end
prefs.edit().putString("completedSurahs", table.concat(arr, ",")).apply()
end
M.loadPairMap = function(key)
local s = prefs.getString(key, "")
local map = {}
if s ~= "" then
for pair in string.gmatch(s, "([^,]+)") do
local a, b = pair:match("^(%d+):(%d+)$")
if a then map[tonumber(a)] = tonumber(b) end
end
end
return map
end
M.savePairMap = function(key, map)
local parts = {}
for k, v in pairs(map) do table.insert(parts, k .. ":" .. v) end
prefs.edit().putString(key, table.concat(parts, ",")).apply()
end
local lastAyahProgress = M.loadPairMap("lastAyahProgress")
M.saveLastAyahProgress = function(surahIdx, ayahNum)
lastAyahProgress[surahIdx] = ayahNum
M.savePairMap("lastAyahProgress", lastAyahProgress)
end
local lastRukuProgress = M.loadPairMap("lastRukuProgress")
M.saveLastRukuProgress = function(surahIdx, rukuIdx)
lastRukuProgress[surahIdx] = rukuIdx
M.savePairMap("lastRukuProgress", lastRukuProgress)
end
local tasbeehCount = prefs.getInt("activeCount", 0)
local tasbeehTarget = prefs.getInt("activeTarget", 33)
local currentWazeefaIndex = prefs.getInt("activeWazeefa", 0)
local tasbeehBeepEnabled = prefs.getBoolean("tasbeehBeep", true)
local tasbeehVibrateEnabled = prefs.getBoolean("tasbeehVibrate", true)
local lifetimeZikrTotal = prefs.getInt("lifetimeZikrTotal", 0)
local lastPlayedSurah = prefs.getInt("lastSurah", 1)
local readingFontSize = prefs.getInt("readingFontSize", 22)
PS.ayahRepeat = prefs.getInt("ayahRepeatCount", 1)
PS.surahRepeat = prefs.getInt("surahRepeatCount", 1)
PS.surahRepeatRem = 0
function saveAyahRepeatCount(v)
PS.ayahRepeat = v
prefs.edit().putInt("ayahRepeatCount", v).apply()
end
function saveSurahRepeatCount(v)
PS.surahRepeat = v
prefs.edit().putInt("surahRepeatCount", v).apply()
end
local savedCity = prefs.getString("userCity", "Abbottabad")
local savedCountry = prefs.getString("userCountry", "Pakistan")
local prayerFajr = prefs.getString("pFajr", "04:10")
local prayerDhuhr = prefs.getString("pDhuhr", "12:15")
local prayerAsr = prefs.getString("pAsr", "16:45")
local prayerMaghrib = prefs.getString("pMaghrib", "19:10")
local prayerIsha = prefs.getString("pIsha", "20:30")
local prayerSunrise = prefs.getString("pSunrise", "06:15")
V25.HIJRI_OFFSET_DAYS = 0
function V25.getHijriOffset() return V25.HIJRI_OFFSET_DAYS end
pcall(function() prefs.edit().remove("hijriDayOffset").remove("hijriOffsetManual").remove("hijriDate").apply() end)
V25.hijriDayOffset = 0
local savedPrayerTimezone = prefs.getString("prayerTimeZone", "Asia/Karachi")
local function slug(s)
local out = tostring(s):gsub("%s+", "_"):gsub("[^%w_]", "")
if out == "" then out = "reciter" end
return out
end
function ft(ms)
ms=tonumber(ms) or 0
local sec=math.max(0,math.floor(ms/1000))
return string.format("%02d:%02d",math.floor(sec/60),sec%60)
end
local function to12Hour(t)
local h, m = t:match("(%d+):(%d+)")
if not h then return t end
h = tonumber(h)
local suffix = (h < 12) and "AM" or "PM"
local h12 = h % 12
if h12 == 0 then h12 = 12 end
return h12 .. ":" .. m .. " " .. suffix
end
M.getPunjabiDate = function()
local punjabiMonths = {"Chet","Vaisakh","Jeth","Harh","Sawan","Bhadon","Asu","Katik","Maghar","Poh","Magh","Phagun"}
local starts = {{3,14},{4,14},{5,15},{6,15},{7,16},{8,16},{9,15},{10,15},{11,14},{12,14},{1,13},{2,12}}
local now = os.date("*t")
local y, m, d = now.year, now.month, now.day
local winStartYear = y
if (m < 3) or (m == 3 and d < 14) then winStartYear = y - 1 end
local boundaries = {}
for i = 1, 12 do
local mm, dd = starts[i][1], starts[i][2]
local yy = (mm < 3) and (winStartYear + 1) or winStartYear
boundaries[i] = os.time({year=yy, month=mm, day=dd, hour=0})
end
local nextWindowStart = os.time({year=winStartYear+1, month=3, day=14, hour=0})
local today = os.time({year=y, month=m, day=d, hour=0})
local monthIdx = 12
for i = 1, 12 do
local upperBound = (i < 12) and boundaries[i+1] or nextWindowStart
if today >= boundaries[i] and today < upperBound then monthIdx = i break end
end
local dayOfMonth = math.floor((today - boundaries[monthIdx]) / 86400) + 1
local nsYear = winStartYear - 1469 + 1
return dayOfMonth, punjabiMonths[monthIdx], nsYear
end
V25.hijriMonthsUrdu = {"محرم","صفر","ربیع الاول","ربیع الثانی","جمادی الاول","جمادی الثانی","رجب","شعبان","رمضان","شوال","ذوالقعدہ","ذوالحجہ"}
V25.hijriMonthsEn = {"Muharram","Safar","Rabi-ul-Awwal","Rabi-ul-Thani","Jumada-ul-Awwal","Jumada-ul-Thani","Rajab","Shaban","Ramadan","Shawwal","Dhul-Qadah","Dhul-Hijjah"}
PS = PS or {}
PS.duaWanted = false
PS.duaGen = 0
PS.duaState = "idle"
PS.duaLastToggle = 0
duaListOverride = nil
V25.uiTextColor = nil
function V25.safeTextColor(v)
if type(v) == "number" then return v end
if type(v) == "string" then
local ok, c = pcall(function() return Color.parseColor(v) end)
if ok and c then return c end
end
return nil
end
function V25.norm(txt)
local t = tostring(txt or "")
t = t:lower()
t = t:gsub("\217\139","") t = t:gsub("\217\140","") t = t:gsub("\217\141","")
t = t:gsub("\217\142","") t = t:gsub("\217\143","") t = t:gsub("\217\144","")
t = t:gsub("\217\145","") t = t:gsub("\217\146","") t = t:gsub("\217\128","")
t = t:gsub("\217\147","") t = t:gsub("\216\140","")
t = t:gsub("[%s%p%c]","")
return t
end
V25.BOOKS = { {n="Qisas-ul-Ambiya - Anbiya ki Kahaniyan (Stories of the Prophets)", l="Urdu", i="Qisas-ul-Ambiya_Stories_of_the_Prophets_Urdu_Audio_MP3_CD_ISO_Image", s="bk_qisas_ul_ambiy", nf=20, q="Sayyidena_Adam - TAKHLIQ-E-QAINAT|Sayyidena_Adam - SHAITAN-KI-DUSHMANI|Sayyidena_Idris - FASAD-KI-IBTEDA|Sayyidena_Nooh - SHIRK-KA-AGAZ|Sayyidena_Saleh - IBRAT-NAK-ANJAM|Sayyidena_Ibrahim - BUT-SHIKAN|Sayyidena_Ibrahim_Ismail_Ishaque - AMAN-WALA-GHAR|Sayyidena_Ibrahim_Loot - BATTARIN-LOG|Sayyidena_Yusuf - HASAD-KI-AAG|Sayyidena_Yusuf - BADSHA-KA-KHAWAB|Sayyidena_Ayyub_Yunus_Zulkifl - SABAR-KA-BADLA|Sayyidena_Musa_Shoaib - KAM-TOLNE-WALEY|Sayyidena_Musa - MUQADDAS-VADI|Sayyidena_Musa - JADUGAR-SE-MUKABLA|Sayyidena_Musa_Harun - SONE-KA-BACHRA|Sayyidena_Musa_Khizar - TEEN-SWAL|Sayyidena_Usha_Ilyas_Ysaa - SANDUQUE-KI-WAPSI|Sayyidena_Dawod_Sulaiman - BE_MISAL-BADSHAHAT|Sayyidena_Uzer_Yahyah_Zakariya - BE_MISAL-BADSHAHAT|Sayyidena_Isah_Jesus - QATL-KI-SAZISH", qp="%02d - Qissa_"},
{n="Seerat-un-Nabiﷺ – Seerah in Urdu", l="Urdu", i="Seerat-un-nabi-seerah-urdu-mp3-audio", s="bk_seerat_un_nabi", d="(01) Arab before Muhammad (s)|(02) Makkah before Muhammad (s)|(03) Shirk before Muhammad (s)|(04) Jews and Christians before Muhammad (s)|(05) Character of people before Muhammad (s)|(06) Story of Elephant|(07) Birth of Muhammad (s) and his family|(08) Childhood of Muhammad (s)|(09) 1st marriage of Muhammad (s)|(10) Muhammad (s)_before_prophethood|(11) Wahi on Prophet Muhammad (s)|(12)_Open_Islamic_invitation|(13) Muslim Hijrah|(14) Muhammad (s) ko qatl karne ke mansoobe|(15) Boycott of Prophet Muhammad (s) and Muslim|(16) Muhammad (s) ka taif ki taraf safar|(17) Muhammad (s) ki dawat per logon ka qubool -e-Islam|(18) Meraaj ka safar|(19) Muhammad (s) se bayt|(20) Muhammad (s) ki Hijrat|(21) Muhammad (s) ki madina me aamad|(22) Masjid e Nabwi ki tameer|(23) Jung e Badr|(24) Jung e Uhad|(25) Musalmanoun se dhoke|(26) Jung e Ahzaab|(27) Suleh Hudaibiyah - Treaty of Hudaibiyah|(28) Jung e Khaybar|(29) Letters of Prophet Muhammad (s) to kings|(30) Fateh Makkah|(31) Jung e Hunain|(32) 9 aur 10 Hijri ke aham waqiyaat|(33) Muhammad (s) ki zindagi ke akhri lamhaat|(34) Ahle bayt ka taaruf ", ss="_-_Seerat-un-Nabi_in_Urdu.mp3", o="23=(23) Jung e Badr_-_Seerat-un-Nabi_in_Urdu.mp3.mp3"},{n="Islamic Duain - Masnoon Duain (Audio)", l="Urdu", i="islamic-dua-in-audio", s="bk_islamic_dua_in", f={"dua-14-shaban.mp3", "dua-after-drinking-water.mp3", "dua-after-eating-dawat.mp3", "dua-after-eating.mp3", "dua-after-exiting-from-the-toilet.mp3", "dua-after-opening-clouds.mp3", "dua-after-receive-debts.mp3", "dua-after-waking-up-from-sleep.mp3", "dua-after-wearing-clothes.mp3", "dua-at-the-time-of-handshake.mp3", "dua-at-the-time-of-iftar-in-dawat.mp3", "dua-at-the-time-of-jamahi.mp3", "dua-at-the-time-of-lunar-eclipse.mp3", "dua-at-the-time-of-rain.mp3", "dua-at-the-time-of-receive-gift.mp3", "dua-at-the-time-of-solar-eclipse.mp3", "dua-at-the-time-of-storm.mp3", "dua-at-the-time-of-sunrise.mp3", "dua-at-the-time-of-sunset.mp3", "dua-at-time-of-rain.mp3", "dua-before-drinking-milk.mp3", "dua-before-drinking-water.mp3", "dua-before-eating.mp3", "dua-before-entering-the-toilet.mp3", "dua-before-sleeping.mp3", "dua-before-starting-new-work.mp3", "dua-for-asking-forgiveness.mp3", "dua-for-entering-house.mp3", "dua-for-entering-masjid.mp3", "dua-for-entering-the-marketplace.mp3", "dua-for-exiting-masjid.mp3", "dua-for-expressing-thanks.mp3", "dua-for-first-ashra-of-ramadan.mp3", "dua-for-payment-of-debt.mp3"}},
{n="Namaz ka Sabaq - Series (Shaykh Mufti Muhammad Saeed Khan)", l="Urdu", i="NamazSeriesByShaykhMuftiMuhammadSaeedKhan", s="bk_namazseriesbys", d="01_Introduction_and_Importance_1|02_Introduction_and_Importance_2|03_Introduction_and_Importance_3|04_Auqat1|05_Auqat2|06_Auqat3|07_Auqat4|08_Auqat5|09_Azan_Iqamat-1|10_Azan_Iqamat-2|11-a_Roohani_Taharat_HujjaTullah_ka_Biyan_12.08|11-b_Roohani_Taharat_HujjaTullah_ka_Biyan_13.08|11-c_Roohani_Taharat_HujjaTullah_ka_Biyan_14.08|11-d_Roohani_Taharat_HujjaTullah_ka_Biyan_19.08.05|11-f_Roohani_Taharat_HujjaTullah_ka_Biyan_21.08|11_Azan_Iqamat-3|12-Wuzu-1|13_Taharat-1_Masail-e-Istanja|14_Taharat-2_Severage_system_gutters_bathrooms|15_Taharat-3_Severage_system_gutters_bathrooms|16_Taharat-4_Water_well_tank_About_clothes_and_carpets|17_Taharat-5_Water_Difference_between_Namaz_of_male_and_female|18_Taharat-6_Water_paki_and_napaki_paki_of_animals_skin_human_and_animals_left_over_food|19_Taharat-7_Animals_leftovers_and_about_bathing|20-Wuzu-2|21-Wuzu-3|22-Bathing-Sunnatain|23-Taharat-11_Wuzu-Sunnatain|24-Taharat-12_Wuzu-Mustahabbat|25-Taharat-13_Wuzu-Complete_method|26-Taharat-14_Wuzu-Naqais|27-Taharat-15_Wuzu-Naqais|28-Juraboun_pur_Massah_1|29-Juraboun_pur_Massah_2|30|31|32|33|34|35|36|37|38|39|40|41|42|43-sajda1|44-sajda2|45-sajda3|47-qaada-akhira-2|48-Qaada-Akhira-3|49|50-Tadeel-e-Arkaan|51-Jumma_1_14.05.2005|52-Jumma_2_15.05.2005|53-Fateha_Khalfulimam_1_20.05.2005|54-Fateha_Khalfulimam_2_21.05.05|55-Fateha_Khalfulimam_3_22.05.2005|56-Fateha_Khalfulimam_4_27.05.2005|57-Fateha_Khalfulimam_5_28.05.2005|58-Fateha_Khalfulimam_6_03.06.2005|59-Fateha_Khalfulimam_7_04.06.2005|60-Fateha_Khalfulimam_8_05.06.2005|61_Fateha_Khalfulimam_9_11.06.2005|62_NASIKH-W-MANSOOSKH_AHADEETH_Kay_ASOOL_10_12.06.2005|63_Fateha_Khalfulimam_11_17.06.2005|64_Fateha_Khalfulimam_12_24.06.2005|65_Fateha_Khalfulimam_13_25.06.2005|66_Fateha_Khalfulimam_14_26.06.2005|67_Fateha_Khalfulimam_15_08.07.2005|68_Fateha_Khalfulimam_16_03.07.2005|69_Fateha_Khalfulimam_17_09.07.2005|70_Fateha_Khalfulimam_18_10.07.05|71_Fateha_Khalfulimam_19_15.7.05|72_Fateha_Khalfulimam_20_17.7.05|73|74|46-qaada-akhira-1", pp="Namaz", ss=".mp3", o="79=namaz46-qaada-akhira-1.mp3"},
{n="Tafseer-e-Quran - Shaikh Hafiz Jalaluddin Qasmi (Kurnool)", l="Urdu", i="HQTafseereQuranByShaikhHafizJalaluddinQasmi", s="bk_tafseer_qasmi", c="bayan", d="10 -11|12|13|14|15|16 A|16 B|17|18|19 A|19 B|1A|1B|20|21|22|23|24|25|26|27|28|29-30|2A|2B|3A|3B|4|5|6|7 A|7 B|7 C|7 D|8 A|8 B|9 A|9 B|9 C", pp="PARAH NO. ", ss=".mp3"},
{n="Seerat un Nabi - Bayan Series (Moulana Muhammad Ilyas)", l="Urdu", i="SeeratUnNabiAudioBayanSeries", s="bk_seerat_bayan", c="bayan", p="Seerat Un Nabi Bayan_%02d.mp3", nf=30},
{n="Seerat-un-Nabi - Moulana Makki Al-Hijazi (Mukammal 40 Parts)", l="Urdu", i="01SeeratUnNabiMo.MakkiAlHijazi_201407", s="bk_makki_seerat40", p="%02d-Seerat-Un-Nabi -Mo.Makki Al-Hijazi.mp3", nf=40, cp="%02d-seerat-un-nabi-Mo.MakkiAl-hijazi.mp3", oc="2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40", o="24=24-seerat-un-nabi-mo.makkial-hijazi.mp3"},
{n="Qasas-ul-Anbiya - Moulana Makki Al-Hijazi (24 Parts)", l="Urdu", i="Sh.MakkiAlHijaziQasasUlAnbiya01of24", s="bk_makki_qasas24", p="Sh. Makki Al-Hijazi - Qasas ul Anbiya - %02dof24.mp3", nf=24, cp="Sh.MakkiAl-hijazi-QasasUlAnbiya-%02dof24.mp3", oc="2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24"},
{n="Tafheem-ul-Quran - Syed Abul A'la Maududi (Mukammal Tafseer)", l="Urdu", i="Tafheem-ul-Quran-by-Syed-Abul-Ala-Moududi-Audio-MP3-CD", s="bk_tafheem_maududi", c="bayan", x={"000 - Introduction - (دیباچہ - Deebacha - مقدمہ - Muqadma).mp3"}, r="hindi"},
{n="A Guide for the New Muslim (English - 12 CDs)", l="English", i="AGuideForTheNewMuslim", s="bk_guide_newmuslim", p="CD %d.mp3", nf=12},
{n="Sahih Muslim - Mukammal Arabic Audio", l="Arabic", i="saheh-muslim-mp3", s="bk_sahih_muslim",d="001sa7e7moslm_ketaabaleeman.mp3|002sa7e7moslm_ketaaba66harah.mp3|003sa7e7moslm_ketaabal7aydh.mp3|004sa7e7moslm_ketaabalsalah.mp3|005sa7e7moslm_kmwade3alsalah.mp3|006sa7e7moslm_ksalatalmosafer.mp3|007sa7e7moslm_kjomo3ah.mp3|008sa7e7moslm_kal3edayn.mp3|009sa7e7moslm_kestesqaa.mp3|010sa7e7moslm_kkosoof.mp3|011sa7e7moslm_kjanaaezz.mp3|012sa7e7moslm_kzakah.mp3|013sa7e7moslm_ksyaam.mp3|014sa7e7moslm_ke3tekaaf.mp3|015sa7e7moslm_khajj.mp3|016sa7e7moslm_kjneka77.mp3|017sa7e7moslm_kradaa3.mp3|018sa7e7moslm_ktalaaq.mp3|019sa7e7moslm_kle3aan.mp3|020sa7e7moslm_kal3etq.mp3|021sa7e7moslm_kboyoo3.mp3|022sa7e7moslm_kmosaqaah.mp3|023sa7e7moslm_kfaraeed.mp3|024sa7e7moslm_khebaat.mp3|025sa7e7moslm_kwa9yeah.mp3|026sa7e7moslm_kannothor.mp3|027sa7e7moslm_kaymaan.mp3|028sa7e7moslm_kqasaamah.mp3|029sa7e7moslm_k7odood.mp3|030sa7e7moslm_kaqdyah.mp3|031sa7e7moslm_kloqa6ah.mp3|032sa7e7moslm_kjehaad.mp3|033sa7e7moslm_kamaarah.mp3|034sa7e7moslm_kassayed.mp3|035sa7e7moslm_kada7ee.mp3|036sa7e7moslm_kashrebah.mp3|037sa7e7moslm_kallebas.mp3|038sa7e7moslm_kalaadaab.mp3|039sa7e7moslm_kasslaam.mp3|040sa7e7moslm_kalalfadh_menalaadaab.mp3|041sa7e7moslm_kasheaar.mp3|042sa7e7moslm_karroeeya.mp3|043sa7e7moslm_kfadaael.mp3|044sa7e7moslm_kfadaaelassa7aabah.mp3|045sa7e7moslm_kalberr.mp3|046sa7e7moslm_kalqadar.mp3|047sa7e7moslm_kal3elm.mp3|048sa7e7moslm_kalthekerwalddo3aa.mp3|049sa7e7moslm_kattawbah.mp3|050sa7e7moslm_kmonafeqeen.mp3|051sa7e7moslm_kaljannah.mp3|052sa7e7moslm_kalfetan.mp3|053sa7e7moslm_kazzohd.mp3|054sa7e7moslm_ktafseer.mp3"},
{n="Khulafay-e-Rashideen - Moulana Makki Al-Hijazi", l="Urdu", i="Sh.MakkiAlHijaziKhulafayARashaydeen01of20", s="bk_makki_khulafa20", p="Sh. Makki Al-Hijazi - Khulafay-a-Rashaydeen - %02dof20.mp3", nf=20, cp="Sh.MakkiAl-hijazi-Khulafay-a-rashaydeen-%02dof20.mp3", oc="2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20"},
{n="Ar Raheeq Al Makhtoom - Safiur Rahman Mubarakpuri", l="Urdu", i="ar-raheeq-al-makhtoom-Safiur-Rahman-Mubarakpuri-urdu-audio-book", s="bk_ar_raheeq", nf=68, q="Arab Aqwaam aur Mahl e Waqu|Arab Hukumatein aur Sardaariyan|Bakhiya Arab ki Sardaariyan|Deen e Ibraheemi mein Qhuraish ki Bidaat|Arboun ke Akhlaq|Khandan e Nabuwat|Wiladat ba Sadat|Ayyam e Shabab|Namoos e Hira|Islam ka Harawwal Dasta|Dawat ke Ibtedahi Marahil|Mushrikeen ke Aeterazat|Zulm o Sitam|Daar e Arqam|Shiddat aur Qubool e Islam|Saudebaziyan aur Qatl ki Sazish|Mahsoori|Gham ka Saal|Beroon e Makkah Dawat e Islam||Shaq ul Qamar aur Meraj|Bait e Aqaba|Hijrat ke Harawal Daste|Ghar se Gaar Tak|Madeene ka Safar|Madeene ke Halat|Naye Muashere ki Tashkeel|Jang ki Ijazat|Saraya aur Ghazwaat||Ghazwa e Badr (Part-2)|Ghazwa e Badr (Part-3)|Ghazwa e Badr (Part-4)|Ghazwa e Badr (Part-5)|Badar ke Baad ki Jangi Sargarmiyan (Part-1)|Badar ke Baad ki Jangi Sargarmiyan (Part-2)||Ghazwa-e-Uhad (Part-2)|Ghazwa-e-Uhad (Part-3)|Ghazwa-e-Uhad (Part-4)|Ghazwa-e-Uhad (Part-5)|Uhad ke Baad ki Fouji Muhimmat (Part-1)|Uhad ke Baad ki Fouji Muhimmat (Part-2)|Ghazwa-e-Ahzaab (Part-1)|Ghazwa-e-Ahzaab (Part-2)|Ghazwa-e-Banu khuraiza|Ghazwa-e-Bani Mustalaq|Waqiy-e-Ifak|Suleh-e-Hudebiya (Part-1)|Suleh-e-Hudebiya (Part-2)|Nayi Tabdeeli (Part-1)|Nayi Tabdeeli (Part-2)|Ghazwa-e-Khaibar (Part-1)|Ghazwa-e-Khaibar (Part-2)|Mazeed Saraya|Jang-e-Mautta|Ghazwa-e-Fateh Makkah|Aaj Koyi Sarzinish Nahi|Makkah Main Qayam aur Wafood|Ghazwa-e-Hunain|Ghazwa-e-Tabook (Part-1)|Ghazwa-e-Tabook (Part-2)|Ghazwaat Par ek Nazar|Allah ke Deen Main|Hajjat-ul-Wida|Rafeeq -ul-Aala ki Janib|Khana-e-Nabuwat|Akhlaaq-o-Aousaaf (Final episode)", qp="Episode %02d _ Ar Raheeq Al Makhtoom - ", o="20=Episode 20 _Ar Raheeq Al Makhtoom - Qabail aur Afrad ko Islam ki Dawat.mp3|30=Episode 30 - Ar Raheeq Al Makhtoom - Ghazwa E Badr (Part - 1).mp3|37=Episode 37 _  Ar Raheeq Al Makhtoom - Ghazwa-e-Uhad (Part-1).mp3"},
{n="Tafsir Ibne Kaseer (Urdu)", l="Urdu", i="Tafsir-ibne-kaseer-kathir-urdu-----audio-mp3-hq", s="bk_ibne_kaseer", c="bayan", x={"000 - Introduction & Biography.mp3"}, r="hindi"},
{n="Bayan-ul-Quran - Dr. Israr Ahmed", l="Urdu", i="BayanUlQuranInUrduByDr.IsrarAhmedAudioMP3-HQ", s="bk_bayan_israr", c="bayan", x={"000 - Introduction - (دیباچہ - Deebacha).mp3"}, r="hindi", x2={"Dua  دُعَاء‎, - Salat Al-Witr.mp3", "Ending Speech - اختتامی تقریر .mp3"}},
{n="Sahih Al-Bukhari - Urdu Tarjuma", l="Urdu", i="Sahih_Al-Bukhari_MP3", s="bk_bukhari94", p="Sahih_Al-Bukhari_%02d.mp3", nf=94},
{n="Sharh Kitab-ut-Tawheed", l="Urdu", i="Sharh_Kitab_Tawheed_3", s="bk_tawheed82", p="%02d.mp3", nf=82},
{n="Riyad-us-Saliheen", l="Urdu", i="riyadussaliheen_202101", s="bk_riyad372", p="Chapter_%03d_Riyad-us-Saliheen_Audio.mp3", nf=372},
{n="Bachon ki Islami Kahaniyan", l="Urdu", i="8YaNabiByAzizMianQawwal", s="bk_bachon_kahani", d="(8) Ya nabi by Aziz mian qawwal|3D Cartoon Video  2 Bakriyon Ki Kahani  Urdu Cartoon Kahani  Kids Corner|ACHHA JI MAIN HAARI CHALO MAAN JAO NA|Aik Karamat - Khwaja Ghareeb Nawaz Ki Karamat - Animated Story|Aurat ke Makro Fareb ki Kahani __ Crocodile Tears __ Faraib Moral Stories|Badshah K 3 Sawal aur Wazeer ki Zindagi ka Soda _ Urdu Story _ Urdu Kahani|Bani Israel  Ki Qaum Bandar Ban Gaye urdu stories _ islamic stories|Cartoon For Kids _ Aqalmand Chidiya _ The Wise Bird _ 3D Animation Video|Cartoon For Kids _ Oont Aur Chohay Ki Ajeeb Khani - Kisi Ko Chota Nahi Samjhain _ Madani Channel|Hazrat Nooh (A.S) Ki Kashti|Hazrat Suleman AS and Hoopoe Bird __ Hud Hud __ Crow __ Solomon in Islam|Heera Aur Chor ( Diamond & Thief ) urdu stories _ islamic stories|How Satan Ride on Noah's ark __ Shytan __ Iblees __ Noah ark __ Kashti|Islamic Stories _ Islamic Stories for Kids in Urdu _ Ghazwa e Uhad ka Waqia|Kabotar k per Lal kyon hotay hain _ pigeon _ red legs _ secret_ knowledge islami malomat Urdu_Hindi|King's Daughter Wedding - Badshah ki Beti ki Shadi ka Sabaq Amoz Aur Dilchasp Waqia By Golden Tips|Madina Sharif ki Ek billi ka Hazoor(S.E.W.W) say ro ro kay Faryaad Karne ka Waqia _ Quran Aur Hadees|Moral Stories for Kids _ Ghuroor Ka Anjaam _ Gadha aur Ghora _ Arrogance And Pride _ Urdu Cartoon|Moral Story for Kids _ Mandak aur Chuhe Ki Ladai _ Aik Ghar Jannat Kay Darmiyan _ Animated Story|Murkh Lomad Panchatantra Stories _ Hindi Animated Stories by Jingle Toons|New Urdu Stories _ Magic Tree & Greedy Man _ Urdu Story For Kids|New Urdu Stories _ Moral Stories _ Hindi Story For Kids|New Urdu Stories _ Moral Stories _|New Urdu Stories _ Moral Stories __001|New Urdu Stories _ Woodcutter & Magic Box _ Urdu Story For Kids|Qissa Aik Chor ka __ Allah ka Banda __ Emotional Story of a burglar __|Sabaq amoz waqia _ Namaz Chorna ka anjam_ urdu stories|Sanp aur mor ko jannat say kyon nikala gya _ snake _ peacock islami malomat Urd_Hindi|Shair Ki Khaal Main Ghadha _ Donkey in the Lion's Skin _ Kids Urdu Story _ Cartoon for Kids(1)|Shair Ki Khaal Main Ghadha _ Donkey in the Lion's Skin _ Kids Urdu Story _ Cartoon for Kids|Sone ka Anda 3D Animated Hindi Stories for Kids _|Sone ka Anda 3D Animated Hindi Stories for Kids __001|Story of a King and His Eagle __ Jahil Budhiya __ Moral Stories __|Story of a King and His Eagle __ Jahil Budhiya __ Moral Stories ___001|Story of king's daughters - Badshah ka apni Beti ko Saza Dene ka Sabaq Amoz Waqia By Golden Tips|Thak Thak Kon Hay Urdu Story _ Bachon ki Kahaniyan & Stories in Urdu _|The Honest Wood Cutter - Aesops Fables Short Story _ Hindi Moral Stories For KIds|The Tale of the Bamboo Cutter in Urdu  Urdu Fairy Tales|Travelling Companion in Urdu _ Urdu Story _ Urdu Fairy Tales|Vulture Bird _ Facts About Vulture _ Interesting Facts About Birds _ Birds Facts _ finch bird|_ Fisherman and his Wife in Urdu _ Urdu Story _ Urdu Fairy Tales|_ Magic Cow in Urdu _ Urdu Story _ Urdu Fairy Tales|_ Miser in the Bush Story in Urdu _ Urdu Fairy Tales|_ New Urdu Stories _ Moral Stories _ Urdu Story For Kids|_ The Tale of the Bamboo Cutter in Urdu _ Urdu Fairy Tales|_ Who will Bell the Cat in Urdu _ Urdu Story _ Urdu Fairy Tales|_ Who will Bell the Cat in Urdu _ Urdu Story _ Urdu Fairy Tales_001|kawa dara howa kyon rehta hai _ islami malomat Urdu_Hindi", ss=".mp3"},
{n="Hadith Collection Bundle", l="Urdu", i="tafseer-ahadees", s="bk_hadith_bundle", d="01 Bukhari Sharif Audio 1|02 Bukhari Sharif Audio 2|03 Bukhari Sharif Audio 3|04 Bukhari Sharif Audio 4|05 Muslim Sharif Audio-1|06 Muslim Sharif Audio-2|07 Mishqath Sharif Audio-1|08 Mishqath Sharif Audio-2|09 Mishqath Sharif Audio-3|10 Mishqath Sharif Audio-4|11 ArbaeenENawawiAll|12 HanfiAhadeesAll", ss=".mp3"},
{n="Jab Zindagi Shuru Ho Gi - Abu Yahya", l="Urdu", i="jab_zindagi_shuru_ho_gi_novel_by_abu_yahya_audio_book", s="bk_jab_zindagi", d="Part No. 01 of 15 _ _Jab ZINDAGI Shuru ho gi_ [ Pa(MP3_160K).mp3|Part No. 02 of 15 _ _Jab ZINDAGI Shuru ho gi_ [ Ar(MP3_160K).mp3|Part No. 03 of 15 _ _Jab ZINDAGI Shuru ho gi_ [ Ma(MP3_160K).mp3|Part No. 04 of 15 _ _Jab ZINDAGI Shuru ho gi_ [ Na(MP3_160K).mp3|Part No. 05 of 15 _ _Jab ZINDAGI Shuru ho gi_ [ 2-(MP3_160K).mp3|Part No. 06 of 15 _ _Jab ZINDAGI Shuru ho gi_ [ Aa(MP3_160K).mp3|Part No. 07 of 15 _ _Jab ZINDAGI Shuru ho gi_ [ Ha(MP3_160K).mp3|Part No. 08 of 15 _ _Jab ZINDAGI Shuru ho gi_ [ Ha(MP3_160K).mp3|Part No. 09 of 15 _ _Jab ZINDAGI Shuru ho gi_ [ Qa(MP3_160K).mp3|Part No. 10 of 15 _ _Jab ZINDAGI Shuru ho gi_ [ Hi(MP3_160K).mp3|Part No. 11 of 15 _ _Jab ZINDAGI Shuru ho gi_ [ Aa(MP3_160K).mp3|Part No. 12 of 15 _ _Jab ZINDAGI Shuru ho gi_ [ Ba(MP3_160K).mp3|Part No. 13 of 15 _ _Jab ZINDAGI Shuru ho gi_ [ Ab(MP3_160K).mp3|Part No. 14 of 15 _ _Jab ZINDAGI Shuru ho gi_ [ Ja(MP3_160K).mp3|Part No. 15 of 15 _ _Jab ZINDAGI Shuru ho gi_ [ Ja(MP3_160K).mp3|Part no 00 of 15 _ Trailer of _ _Jab ZINDAGI Shuru ho gi by Abu Yahya.mp3"},
{n="Naatein - Junaid Jamshed", l="Urdu", i="Jalwa-e-Janan_JunaidJamshed", s="bk_naats_jj", c="naat", d="01. Jalwa-E-Janan|02. Muhammad Ka Roza|03. Tune Poochi Hai Imamat|04. Jaga Ji Lagane Ki Duniya|05. Multazim Par Dua • Ilahi Teri Choukhat Par |06. Qad Af Lahal (Surah Muminoon)|07. Yeh Subh-E-Madina|08. Rasha Makawa (Pushto)|09. Madad Meray Allah|10. Jalwa-E-Janan (Extended Version)", ss=".mp3"},
{n="Qasas-ul-Anbiya - Moulana Makki Al-Hijazi (Recording 2, 24 Parts)", l="Urdu", i="QasasUlAmbiya-as", s="bk_qasas24_r2", p="Sh. Makki Al-Hijazi - Qasas ul Anbiya - %02dof24.mp3", nf=24},
{n="Hisnul Muslim - Azkaar o Duain (133 Parts)", l="Urdu", i="Hisnul_Muslim_with_Urdu_Translation_Audio-Book", s="bk_hisnul_muslim", d="1.NeendSeJagneKeAzkaar|10.GherSeNikelteWaqtKeAzkaar|100.OonchiJaghounPerChedteWaqtTakbeerAurUtarteWaqtTasbeehKehna|101.MusaafirKiDuaJabWohSubhaKare|102.SafarWaGhairahMeinJabKisiManzilPerUtre|103.SafarSeWaapsiKiDua|104.KhushKarneWaliYaNaPasandeedahCheezPeshAnePerKyaKahe|105.RasoolAllahPerDoroodBhejniKiFazeelath|106.SalaamKoAamKarna|107.MuraghKiBaanghSneAurGadheKaHingnaSuneToKyaKahe|108.RaathKoKottaounKaBhoknaSunkarKyaDuaKarniChaahie|109.UsShakhsKeLiyeDuaJiseTumneGaliDiHo|11.GherMeDaakhilHoteWaqtZikr|110.JabKoiMuslimKisiMuslimKiTareefKareToKyaKahe|111.RukneYamaaniAurHajreAswadKeDarmiyaanKiyaDuaMange|112.SafaAurMarwahPerTherneKiDuA|113.ArafahYane9ZilHijjahKoDua|114.MshareHaraamKePaasZikr|115.JamraounKoKankerMaarteWaqtHerKankerKeSaathTakbeerKehte|116.HajreAswadWaleKonePerTakbeer|117.DushmenKeLiyeBaddua|118.KoiAgerKisiSeyDareToKyaKahe|119.TajjubKeWaqtAurKhushKunKaamKeWaqtKyaKahe|12.MasjidKiTarafJaaneKiDua|120.JisShakhsKePaasKhushKarneWaliKhaberAaeToWohKyaKare|121.JoShakhsApneJismMeDerdMehsoosKareWohKyaKaheAurKyaKare|122.JoKisiCheezKoApniNazerLagjaneSeDareWohKyaKahe|123.DameemahJameAkhlaaqWaAdaabKaBayaan|124.MuhrimShakhsHajjYaUmreMeTalbiyahyaneLabbaikKaiseyKahe|125.GhabraahetKeWaqtKyaKahe|126.JabKaafirKoCheenkAaeToUseKyaKahe|127.JabKaafirSalaamKareToUseyKyaJawabDe|128.RozedarKoiShakhsGaliGalojKareToKyaKahe|129.ZabhYaNeharKarteWaqtKyaKahe|13.MasjidMeDaakhilHoneKiDua|130.SarkashShaitanounKeKhufyaTadbeerounKeTodKeLiyeKyaKahe|131.IstighfaarAurTaubahKaBayaan|132.TahleelTakbeerAurTasbeehKiFazeelate|133.RasoolAllahTasbeehKisTarhaPadhaKarteThey|14.MasjidSeNikalneKiDua|15.AzaanKeAzkaar|16.DuaIstiftaahYeneTakbeerKeBaadSureFatihaSePehlePedheJaneWaleAzkaarAurDuae|17.RokooKiDuae|18.RokooSeUthneKiDuae|19.sajdeKiDuae|2.LibaasPehenneKiDua|20.DoSajdaounKeDarmiyaanKiChendDuae|21.SajdaeTilaawatKiDuae|22.Tashahhud|23.PehleTashahhudKeBaadRasoolAllahPerDorood|24.AkhriTashahhudKeBaadSalaamSePehleKiDuae|25.NamaazSeSalaamKeBaadKeAzkaar|26.FajrKiNamaazKeBaad|27.NamaazeIstikharaKaTarikhaAurUsmePedhiJaaneWaliDua|28.SubhWaShaamKeAzkaar|29.SubhWaShaamKeAzkaar|3.NayaLibaasPehenneyKiDua|30.SoneSePehleKeAzkaarAurDuae|31.RaatPehloBadelteWaqtKyaKahe|32.NeendMeBechainiAurGhbraahatKiDuaAurWehshatWaghairahKiDua|33.AcchaYaBuraKhwaabDekheToKyaKare|34.BuraKhwaabDekhkerKiyeJaneWaleAmaal|35.QonooteWitrKiDuae|36.WitrSaySalaamKeBaadDua|37.GhamAurFikrKiDua|38.BeqaraariKiDua|39.DushmanAurHukoomathWaleSeMilneKiDua|4.NayaaLibaasPehenneyWaleKoKyaDuaDiJaae|40.JiseEmaanMeShekHoneLageUskiDua|41.KharzKiAdaaigiKeLiyeDua|42.NamaazMeYaQuranKiTilaawathKeWaqtWaswasaAaeToKyaDuaKare|43.usShakhsKiDuaJisPerKoiKaamMushkilHojae|44.KoiAgerGonaahKerBatheToKyaKaheAurKyaKare|45.WohDuaeJoShaitaanAurUskeWaswasounKoDoorKartiHai|46.JabKoiMarziKeKhilaafWaqiahHojaeYaKoiKaamTaaqathWaIkhtiyaarKeBaherHoToKyaKah|47.BacchounKoKinKalimaathKeSaathAllahKiPanaahMeDiyaJaae|48.BemaarPursiKeWaqtMareezKeLiyeDua|49.BemaarPursiKiFazeelath|5.LibaasUtaareToKyaKahe|50.UsMareezKiDuaJoApniZindagiSeNaUmmeedHochokaHo|51.QareebulMauthShakhsKoTalqeen|52.JiseKoiMuseebathPohncheUskiDua|53.MayyithKiAnkheBandhKerteWaqtKyaDuaPedhe|54.MayyithPerJanaazahAdaKarteWaqtKiDuae|55.BacchePerJanazeKiDua|56.TaziyathKiDua|57.MayyitKoQabrMeDaakhilKarteWaqtDua|58.MayyitKoDafnKarneKeBaadKiDua|59.QabrKiZiyaarathKiDua|6.QadaaeHajatKeLiyeBaitulKhalaMeDakhilHoteWaqtKyaKhe|60.HawaaChelteWaqtDua|61.BadalGarjeToKyaPedhe|62.BaarishKiChendDuae|63.BaarishUterteWaqtKiDua|64.BaarishUterneKeBaadKiDua|65.MatlaSaafKarneKeLiyeDua|66.JabPehliTaareekhKaChaandDekheToYehDuaPedhe|67.RozaKholneKeWaqtKiDuae|68.KhaneAurPeeneSePehleKiDuae|69.KhaneSeFaarighHoneKeBaadKiDuae|7.QadaaeHajatYaneBaitulKhalaSeNikleToKyaDuaPedhe|70.KhaanaKhilaneWaleKiLiyeMehmaanKiDua|71.JoShakhsKuchPilayeYaPilaneKaIradahKareUskeLiyeDua|72.JabKisiGherWaloKehanRozaIftaarKareToYehDuaPedhe|73.DuaJabKhanaHazirHoAurRozedaarRozaNaKhole|74.nayaPheDekhneKeWaqtKyaDuaPedhiJae|75.CheenkKiDua|76.ShaadiKarneWaleKeLiyeDua|77.ShaadiKarneWaleKiApneLiyeDuaAurSawariKhareedneKiDua|78.JimaaYaneBiwiSeSohbathKareToKyaKahe|79.GhussayKiHaalathMeKyaDuaPedhe|8.WadooSePehleZikr|80.JabKoiMuseebathzadahKoDekheToKyaKahe|81.MajlisMePedhneKiDua|82.MajlisKeGunaahDoorKarneKiDua|83.WohKalimaathJinKeSaathTamaamMajaalisKhatmKarniChahiye|84.JoShakhsKaheAllahTujheBakhsheUskeLiyeKyaDuaKare|85.JoAchhaSolookKareUskeLiyeKyaDuaDeniChahiye|86.WohZikrJiskeSaathAdmiDajjalKeFitneSeMahfoozRahega|87.JoShakhsKaheMujheTumseAllahKeLiyeMohabbatHaiUskeLiyeDua|88.JoShakhsTumhareLiyeApnaMaalPeshKareUseKyaDuaDeniChahie|89.KhrarzAdaKarteHoeKharzAdaKarneWaleKeLiyeDua|9.WadooKeBaadKeAzkaar|90.ShirkSeKhaufKiDua|91.JoKisiKoTuhfaDeYaSadqaKareAurUskoDuaDiJaeToKyaKahe|92.BadhFaaliKiKaraahathKiDua|93.ChopaeYaKisiSawariPerSawaarHoneKiDua|94.SaferKiDua|95.BastiYaShaherMeDakhilHoneKiDua|96.BazaarMeDaakhilHoneKiDua|97.JanwarYaSawaariGireToKyaKahe|98.MusaafirKiMuqeemKeLiyeDua|99.MuqeemKiMusaafirKeLiyeDua", ss=".mp3"},
{n="Munajat - Dawat-e-Islami (17 Munajat)", l="Urdu", i="MunajatOfDawatEIslami", s="bk_munajat17", d="11824|12111|13859|13870|14658|14735|15001|15313|19171|19666|20836|22405|22679|24172|24685|25454|25874", ss=".mp3"},
{n="Naatein - Mufti Akhtar Raza Khan (Taajush Shariah, 67)", l="Urdu", i="TaajushShariahNaats", s="bk_naats_akhtar67", c="naat", d="Ajab Rang par hay Bahar-e-Madinah|Allah Allah Allah Hoo 1989|Allah Allah Allah Hoo 1998|Allah Allah Allah Hu|Apnay Rindon Ki Ziyafat|Arsh-e-Haq Hay Masnad-e-Rifat Rasoolullah ki|Chaand Se Unn Ke Chehray Par|Chand Se Unn Ke Chehray Par|Complete Qasida Burdah|Daagh-e-Furqat-e-Taybah|Dar-e-Janaan pe fidai ko|Dil dard se bismil ki tarha|Furqat-e-Taybah Ki Wehshat|Jahan Baani Ataa Kar Dein - Very First Recitation|Kash Gumbad-e-Khazra|Khayr al-Bariyyah with Shaykh Fazlur Rahman Al Madani|Kuch Aisa kar de Meray Kirdigar Aankhon Mein|Lam Yati Nazeeruka|Lam Yati Naziruka|Madinah Aanay Wala Hay|Madinay Chalain|Main Madeenay Ko Chaloon|Manqabat Ghous-e-Paak|Mar Ke Jeenay Ka Paaon Maza 1989|Mast-e-Maey Alast hay|Mawla Ya Salli Wa Sallim 1994|Meray Allah Ke Nigaar Salam 1994|Mere Allah ke Nigar Salam|Mufti-e-Azam ka Taqwa chorr kar|Mufti-e-Azam ka Zarra kia bana Akhtar Raza|Mufti-e-Azam-e-Deen-e-Khair-ul-Wara|Mufti-e-Azam-e-Deen-e-Khayr-ul-Wara|Munawwar Meri Aankhon Ko|Munawwar Meri Ankhon ko|Mustafa Jaan-e-Rehmat 13-02-2004|Mustafa Jaan-e-Rehmat 20-02-2004|Mustafa Jaan-e-Rehmat|Mustafa-e-Zaat-e-Yakta 03-04-2003|Mustafa-e-Zaat-e-Yakta 1989|Mustafa-e-Zaat-e-Yakta Aap Hain|Nazar par kisi ki Nazar 1989|Nazar pe kisi ki Nazar|Nihan jis dil mein|Payam le ke jo aaee saba Madinay se|Phir Ke Gali Gali Tabah|PunjabiKalamWithAtifRazaMalawi|Qasidah Burdah 1989|Qasidah Burdah Sharif|Qasidah Burdah|Salat o Salam 30-08-1991|Sambhal Ja Aey Dil-e-Muztar 1989|Sambhal Jaa Aey Dil-e-Muztar|Sar Soo-e-Rauza Jhuka with Sharha|Sar Soo-e-Rauza Jhuka|Shameem-e-Zulf-e-Nabi|Shamim-e-Zulf-e-Nabi|Talaatum hay ye kesa|Teri Chokhat Pe Jo Sar|Tu Sham-e-Risaalat Hay 1992 Colombo|Tum Pe Karrorron Durood|Woh Abr-e-Bahar Aya|Woh Barrhta Saya-e-Rehmat Chala|Woh Raza ke Nezay ki maar hay|Ya Mujeebu Ya Mujaabu|Ya RasoolAllah Ya Khayr al-Anaam|Zameen-o-Zaman Tumharay Liye|Zindagi ye nahin hay kisi ke liye", ss=".mp3"},
{n="Naatein - Owais Raza Qadri (257 Naats, Mukammal)", l="Urdu", i="NaatsOfRasool-Ul-ALLAHMuhammadOwaisRazaQadriCollectionOfMixNaats", s="bk_naats_owais257", c="naat", ow=true, ow2=",253,254,255,256,257,", d="001AAGAYESARKAR-OwaisQadri.mp3|002AaeyAaqaMadniAaqa|003Aahista_chal|004Aahista_chal_long|005Aahista_chal2|006Aaishafae_umam|007Aaj_aaye_nabiyon_ke_sardar|008Aakuchsunadeishq|009AamadAamadHePart1|010AamadAamadHePart2|011Aamnakalaalaagaya|012Aaqap.b.u.hAayeMadniAaqa|013Aarizey_shamsoqamar|014Aasmaan_gar_terey_talwoonka|015Abmerynigahonmain|016Aisa_tujhay_khaliq|017Ajab_karam|018Ajab_rang_a|019Ajab_rang_b|020Ajab_rang_c|021Ajab_rang_per_hai|022Alifallah|023AllahAllahShah-e-konain|024AllahAllah|025AllahHooAllahHoo|026AllahHooDumBaDumAllahHoo|027AllahNabiDaNaamLiye|028AllahTaalasNames|029Allah_hoo_allah|030Allah_nabi_da_naam_liye|031AllahoRabboMuhammadin|032An_nabi_sallo_ale|033Anwar|034ApnaGhumYaShah-e-ambiya|035ArshMereHazoor|036Arzo_saman_banay_hain|037Ay_sabz_gumbad_walay|038Baatjokijiye|039Bage_jannat_main|040Bagh-e-chamanMeinNirali|041Baharein|042Balagalula_bekamalehi|043Balaghal-ulaBikamalihi|044BehtheUthteNabiKiGuftaguKerteRahe|045Bethtay_uthtay_nabi_ki|046BharLoJholian|047Bhini_suhani_subho_main|048Bigdibanaomakkimadani|049Bulla_lo|050Chalo_madinay_chaltay_hain|051Chamak_tujhse_patay_hain|052Chour_fikar_dunya_ki|053DarPeBulaaoMakkiMadni|054Dar_pe_bulaao_makki_madani|055DilMainHooYaadTeri|056DilMeinHoYaadTeri|057DilMeraDuniyaPeShedaHoGiya|058DilWichAllahAllah|059Dil_dard_se_bismil|060Dil_main_ho_yaad_tery|061Dil_mera_dunya_pe_sheda_hogaya|062DuniyaJagmaganeAe|063Duwa|064Elahi_madad_kar|065Gam_nahi_chordey|066Gham_sabhi_rahto|067Ghum_ho_gae_beeshumaar|068GunaahonKiAadatChuraMairayMola|069GunaahonKiAadat2|070GunaahonKiNahinJatiHaiAadatYaRasoolallah|071GunnahonKiAadat|072HaajionAaoShehenshah|073Habibe_khuda_ka_nazara|074Ham_per_nazar|075Hamd|076Haqiqatmainwo|077HarWaqtTasvur|078Har_dam_ho_mera_wird|079Har_waqt_tasavur_main|080Hariltijasepehlay|081Hazir_hey_darey-daulat|082HerWaqatTasavoorMain|083Hokaramsarkar|084Huzoor_aisa_koi_intizaam|085IshqKeRangMe|086JabHusn|087Janatmainnahikhencho|088Jub_gumbade_khazrape|089Jub_gumbade_khazrape_long|090KaabayKayBadrudduja|091Kaabe_ke_badr_ud_oja|092Kaabe_ke_badr_ud_oja_new|093KaashDekhneKoMilJata|094Kab_gunahon_say|095Kabhi_rozay_se_mimber_tak|096Kaliazulfawala|097Karoon_dam_badam_main|098KhilaMereDilKiKaliGooseAzam|099Khusaamdeed_khusaamdeed|100Kiamuzdajaanbuksh|101Kionrazaaajgali|102Kuch_aisa_kardey_meray|103LaMaujoodaIllahLah|104Lagateyheynaara|105LikhRahaHoonNaat-e-sarwar|106MadaniMadineWale|107Madina_yaad_aya_hay|108Madinay_diyan_pak_galyan|109Mahboob_da_maila_hay|110Mahenooragayamarhaba|111MainJoYounMadeneJata|112MainMadeeneChalla|113MainSoJaon|114Main_jo_uon_madinay_jata|115Mainmadeenaychala|116Manghte_khali_hath|117MangneKaMazaHeDerbarPer|118Mangne_ka_maza_hay|119Mankabat1|120Mankabat2|121Mankabat3|122Mankabat4|123Mankabat5|124Marhaba_marhaba_ki|125Marhababolomarhaba|126Meem_e_madina|127Meeran_walion_kay_imam|128Mehfil_e_naat_main_akar_bheta_karo|129MeinSoJaaon|130Menoo_majboorian|131MeraAaqap.b.u.haayeJhoomo|132Meray_sarkar_mery_baat|133Merayaqaaaijhoomo|134MereAaqaAe|135MereNoorKa|136Mere_aaqa_nigahe_karam_ho|137MeriDherkenMainYaNabipbuh|138Meri_kismat_ko_jagado|139Mery_dharkan_main|140MuhammadOwaisRazaQadri|141MuhammadOwaisRazaQadri2|142MujhayNaikInsaanBanaMereMola|143Mujhay_darpe_phir_bulana|144Mujhko_darpesh_hay|145Mujrime_haibat_zada|146Munkabat7|147Muradain_mil_rahi_hain|148MustafaJaan-e-rehmat|149Muzdawaaiasion|150Na_arshe_aman|151Na_ho_araam_jis_beemaarko|152Naat_aj_aye_nabi_laj_pal_haqaonline|153Naat_dar_pe_bulao_www.haqaonline.com|154Naat_kabhi_mujh_par_bhi_ho_rehmat_haqaonline.com_|155Naat_madine_diyan_pak_galiyan_www.haqaonline.com|156Naat_main_mangta_hoon_www.haqaonline|157Naat_menoon_aap_sahara_de_haqaonline.com_|158Naat_meri_baat_ban_gayee_hae_haqaonline.com_|159Naat_sarian_thoo_uchi_teri_shan_haqaonline.com_|160Naat_sarkar_ko_ro_ro_kar_haqaonline.com_|161Naat_ya_rasool_allah_rahmat_ki_nazar_ha|162NabiKaJhanda|163Naimatain_bant_ta|164NoorKa|165Nooragaya|166Noori_mehfil_pe_chadar|167Noorseapnayserver|168OwaisQadriLive|169Paat_woh_kuch|170PalakKeNazaro|171PhirGumbad-e-khazraKiFizaon|172Phir_madinay_ka_mujhko_bulawa_mila|173Phirkey_gali_gali_taba|174Phirnakarwatli|175Qaafley_waley_ne|176Qadirasarwararahnuma|177Qaseeda-e-noor|178Qaseedah-e-mairaj|179Qasida_burda_shareef|180Qasida_mairaj|181Qurbanmainunkibakshishpe|182Rab_mehfala_sajayan_ne|183Rahay_jatay_hain_ye_armaan|184Rokletihayapkinisbat|185Rouk_laiti_hai_apki_nisbat|186Roza_ae_aqdas_ki_talabgar|187Rukh_din_hey_yamehrey_saman|188SabSeAalaHoAalaHamaraNabipbuh|189Sachi_baat|190Sada-e-merhaba|191Salam|192Salam1|193Salealanabiyena|194Sallay_aala|195SareGunaahGaran|196SarkarKiAamadMarhaba|197Sarkarkaydarperjaaon|198Sartaba_karam_hey|199Seraygulshankondekhay|200Serverkahoonkay|201Serware_ambia_mazhare_kibriya|202ShalaWasdaRawayTeraSonaHaram|203Shukrey_khuda|204Sochta_hoon_main_wo_ghari|205SoonaJungleRaatAndheri|206Subha_taiba_main_hovi|207TaireeWehashtoonSay|208TajdareHaramAeShensha|209Tera_milad_main_kion_na_manawan|210TeriYaadPayee|211Teri_jaalyon_ke_neechey|212Teri_wahshaton_se_aey_dil|213Tery_yaad_pae|214ToShamERisalatHai|215Tooba_may_jo|216TuShamm-e-risalatHai|217Tu_shame_risalat_hay|218Tuhmara_naam_musibat|219TumharaNaamMuseebatMain|220Tumharey_zarrey|221TumhinAareshPeJaneWale|222Unkimehaknaydilkay|223Wah_kya_joodo_karam_hey|224Wahkiabaatismahinayki|225WhoJoNaaTheToKuchBhiBhiNaTha|226Wo_soay_lalazar_phirtay_hain|227Woh_kamal_husn_huzoor|228Woh_kamal_husn_huzoor_hay|229Woh_sue_lalazaar|230Wohirubhayjisne|231YaIllahiRang|232YaNabiSalamAlaika|233YaRabMereDilMein|234YaSayyedi|235Ya_allah_ho_ya_allah|236Ya_rab|237Ya_rab_hay_yehi_dilki_sada|238YaadMainTeri|239Yahabibi_noore_mujassam|240Yamustafakhudara|241Yarasoolalah|242Yarasoolalah_akar_dekhlo|243Yarasoolalah_ka_naara_lagatey_jaaingay|244YeKehtiThiHarGharMeinJaKarHaleema|245Ye_kehti_thi_ghar_ghar|246YehKisShehnshaheWalaKi|247Yeh_aarzo_nahi|248Yeikramhay|249Yekisshehanshahki|250Zahay_izat|251Zah-e-muqaddar|252ZairayKoyeJinaLong|253AeyBayabanEArabTeriBaharonKoSalam|254AqaaKonNazroonPeCharheyDekhKe|255KalamEBahoo|256MujhKoDarpeshHaiPhirMubarakSafar|257MujhKoDarpeshHaiPhirMubarak"},
{n="Naatein - Islamic Academy (249 Naats)", l="Urdu", i="Islamicacademy.orgNaats", s="bk_naats_islacad", c="naat", d="001Aagaey_mustafa-khursheedAhmad|002Aajsikmitradi-khursheedAhmad|003Allahallahallahhu-khursheedAhmad|004Aya_hay_bulava-khursheedAhmad|005Basahuahainabikadiyar-khursheedAhmad|006Chal_madeenay-khursheedAhmad|007Harwaqttasawwurmein-khursheedAhmad|008Jashn_e_aamad_e_rasool-khursheedAhmad|009Jo_na_haota-khursheedAhmad|010Khairul_bashar_per-khursheedAhmad|011Kiyakhabarkiyasaza-khursheedAhmad|012Kuchnaheenmaangta-khursheedAhmad|013Meinsojaaoyamustafakehtaykehtay-khursheedAhmad|014Mujhkobhikash-khursheedAhmad|015Nabikayishqnay-khursheedAhmad|016Reham_karo-khursheedAhmad|017Sallayallapukaro-khursheedAhmad|018Sallooalaihewaalaihee-khursheedAhmad|019Sehraygulshankaundekhay-khursheedAhmad|020Shah-e-medina-khursheedAhmad|021Shanabhalakaundasay-khursheedAhmad|022Sozaydilchahayay-khursheedAhmad|023Submilkarbolosallayala-khursheedAhmad|024Teraydarkameingadahoon-khursheedAhmad|025Ya_sallay_alla_mehboob_e_khuda-khursheedAhmad|026Ya_shah_e_umam-khursheedAhmad|027Yeh_naaz-khursheedAhmad|028Yehkaramhay-khursheedAhmad|029Zameenozamaan-khursheedAhmad|030Bariumeedhay-imranSheikhQadri|031Dilmainhayarzoowmadinah-imranSheikhQadri|032Hamkoallahaurnabisay-imranSheikhQadri|033Kitthaymehreali-imranSheikhQadri|034Kiyonkarnahomakehsay-imranSheikhQadri|035Konkehtahayaankhain-imranSheikhQadri|036Mairijaanibbihhonigahekaram-imranSheikhQadri|037Nahoaraamjisbeemarko-imranSheikhQadri|038Rahmatallilaalameen-imranSheikhQadri|039Aapaaqaonkayaaqa-shakeelAttari|040Ahlaoonwasahlaoon-shakeelAttari|041Ankhainrorokaysujanaywalay-shakeelAttari|042Ayrehmatedoalam-shakeelAttari|043Bariummeedhay-shakeelAttari|044Hamkoallahornabisaypyarhay-shakeelAttari|045Hubbaydunyasaybacha-shakeelAttari|046Jaldhihamaazmimadinahhongay-shakeelAttari|047Mujhaydarpayphirbulana-shakeelAttari|048Mujhkoponhchaday-shakeelAttari|049Nizahkisakhtiyan-shakeelAttari|050Pehlaysarkaarkimehfilko-shakeelAttari|051Phirsaybulaojald-shakeelAttari|052Phonchoonagarmainrozaay-shakeelAttari|053Aamnakalaalaagaya-fasihudeenSeharwardi|054Aarahahayyehhajjkamaheena-fasihudeenSeharwardi|055Aaysabzgumbadwalay-fasihudeenSeharwardi|056Aeyishq-e-nabimeraydilmeinbhisamajaana-fasihudeenSeharwardi|057Ali_ali-fasihudeenSeharwardi|058Apniatakahaqnayyehmanzar-fasihudeenSeharwardi|059Apnifardeamaldekhkar-fasihudeenSeharwardi|060Arshkeeaqaldanghay-fasihudeenSeharwardi|061Ay_bahaaray_taiba-fasihudeenSeharwardi|062Balaghalulabeekamalihi-fasihudeenSeharwardi|063Baykaleemittgayee-fasihudeenSeharwardi|064Bhardaymaeulfatsay-fasihudeenSeharwardi|065Bheek_lay_kay-fasihudeenSeharwardi|066Bigdibanaomakkimadani-fasihudeenSeharwardi|067Chamak-fasihudeenSeharwardi|068Dil_maqaamay-fasihudeenSeharwardi|069Dil_saraapa_bahaar-fasihudeenSeharwardi|070Dile_figaar-fasihudeenSeharwardi|071Dilmeinhoyaadteri-fasihudeenSeharwardi|072Eidemiladunnabihay-fasihudeenSeharwardi|073Fatimabint-e-rasool-e-kaainaat-fasihudeenSeharwardi|074Hasbirabbijallallah-fasihudeenSeharwardi|075Hay_chaman-fasihudeenSeharwardi|076Innilti_yaroah-us-sabah-fasihudeenSeharwardi|077Iznaytaibamujhaysarkar-fasihudeenSeharwardi|078Jubbhinazaruthaaoon-fasihudeenSeharwardi|079Kab_dikhao_gay-fasihudeenSeharwardi|080Khuda_jab_khud-fasihudeenSeharwardi|081Kon_rutbay_main-fasihudeenSeharwardi|082Madeenaywaalaymeraylajpal-fasihudeenSeharwardi|083Mainjoyoonmadinayjaata-fasihudeenSeharwardi|084Mainmedinayjaoonga-fasihudeenSeharwardi|085Mairajsaafsaafsadaqatkibaathay-fasihudeenSeharwardi|086Meramaahikaditayaawayga-fasihudeenSeharwardi|087Merapanjatankosalamhai-fasihudeenSeharwardi|088Merisochteyveeooncha-fasihudeenSeharwardi|089Molayasalliwasallim-fasihudeenSeharwardi|090Mujhkotofeeqezikrenabi-fasihudeenSeharwardi|091Mustafa_jaanay_rehmat-fasihudeenSeharwardi|092Naam-e-mohammadliyakaro-fasihudeenSeharwardi|093Naemtenbantajissimt-fasihudeenSeharwardi|094Paish_haq-fasihudeenSeharwardi|095Quranepaakkiazmat-fasihudeenSeharwardi|096Roshini-fasihudeenSeharwardi|097Sanu_apna-fasihudeenSeharwardi|098Sarkarmedinaywalay-fasihudeenSeharwardi|099Sarkaryehnaamtumhara-fasihudeenSeharwardi|100Sarmaya-e-bahar-fasihudeenSeharwardi|101Sehreghulshankondaikhay-fasihudeenSeharwardi|102Sooyetaiba-fasihudeenSeharwardi|103Sozay_bilal-fasihudeenSeharwardi|104Sunherijaaliyonkoabnazar-fasihudeenSeharwardi|105Talaalbadrualaiyna-fasihudeenSeharwardi|106Tasavvuraat_main-fasihudeenSeharwardi|107Tumhaara_saani-fasihudeenSeharwardi|108Tumhari_shaan_ka-fasihudeenSeharwardi|109Ummatihoonmainnabika-fasihudeenSeharwardi|110Woh_hi_dayaar-fasihudeenSeharwardi|111Woh_lamhay-fasihudeenSeharwardi|112Wohrozaeaqdaskaymeenar-fasihudeenSeharwardi|113Yaad_e_sarkaar-fasihudeenSeharwardi|114Yanabihamgunahgaroonko-fasihudeenSeharwardi|115Yanabinazreinayatkijiey-fasihudeenSeharwardi|116Yanabiyanabi-fasihudeenSeharwardi|117Yarasoolallaheunzurhaalana-fasihudeenSeharwardi|118Yarubbemohammadmeritaqdeer-fasihudeenSeharwardi|119Yarubmujhaysarkarkadeewana-fasihudeenSeharwardi|120Yashafeealvarasalaamunalaik-fasihudeenSeharwardi|121Zahay_izzato-fasihudeenSeharwardi|122Zara_karo-fasihudeenSeharwardi|123Zikrnabidakarye-fasihudeenSeharwardi|124Aa_gayay_mustafa-mushtaqQadri|125Aamnakalaalaaya-mushtaqQadri|126Aaomilkarjashneviladat-mushtaqQadri|127Aay_saba_lay_ja-mushtaqQadri|128Aay_saba_mustafa_say-mushtaqQadri|129Ay_meray_malik-mushtaqQadri|130Ay_naame_mohammad-mushtaqQadri|131Ay_shehanshahe_madinah-mushtaqQadri|132Baarah_rabiul_awwal-mushtaqQadri|133Bhardo_jhoali-mushtaqQadri|134Bigdibhibanaengay-mushtaqQadri|135Chalmadeenaychaltayhain-mushtaqQadri|136Chalnabidaydartay-mushtaqQadri|137Chalo_diyare_nabi-mushtaqQadri|138Chalo_madeenay-mushtaqQadri|139Chalyeshahemadiny-mushtaqQadri|140Do_sadqae_deedar-mushtaqQadri|141Fajr_ka_waqt-mushtaqQadri|142Ham_ko_apni-mushtaqQadri|143Ham_per-mushtaqQadri|144Haqeeqat_mein-mushtaqQadri|145Har_nazr-mushtaqQadri|146Hum_faqeeron_ko-mushtaqQadri|147Imanhaiqaal-mushtaqQadri|148Imdad_kun-mushtaqQadri|149Jagah_ji_laganay-mushtaqQadri|150Jashnaamaderasool-mushtaqQadri|151Kaun_kehta_hay-mushtaqQadri|152Khairul_bashar_per-mushtaqQadri|153Kiddanaamemohammad-mushtaqQadri|154Kiyakhabarkiyasaza-mushtaqQadri|155Koi_gul-mushtaqQadri|156Lab_per-mushtaqQadri|157Lailaha_illallah-mushtaqQadri|158Lum_yatee-mushtaqQadri|159Madani_qaafilah-mushtaqQadri|160Madeenay_ki_taraf-mushtaqQadri|161Marhabayamustafa-mushtaqQadri|162Maymarkayvee-mushtaqQadri|163Mehboobe_kibriya_say-mushtaqQadri|164MeraySarkarAagaay-mushtaqQadri|165Merayaaqajiana-mushtaqQadri|166Mustafa_jaanay_rahmat_1-mushtaqQadri|167Mustafa_jaanay_rahmat_2-mushtaqQadri|168Naimatainbantajissimt-mushtaqQadri|169Neemittiaymadinaydiay-mushtaqQadri|170Nigahe_karam_ho-mushtaqQadri|171Paishehaqmushdashifaat-mushtaqQadri|172Phiruthawalwala-mushtaqQadri|173Qaseedae_noor-mushtaqQadri|174Qaseedah_burdah_p1-mushtaqQadri|175Qaseedah_burdah_p2-mushtaqQadri|176Qaseedahe_ghausia-mushtaqQadri|177Quflay_madinah-mushtaqQadri|178Raahi_sher_madinay-mushtaqQadri|179Saadayvalsonaya-mushtaqQadri|180Saaraynabionkasarvar-mushtaqQadri|181Sabsayaulaoaala-mushtaqQadri|182Saire_gulshan-mushtaqQadri|183Sarvar_kahoon-mushtaqQadri|184Shahe_konain-mushtaqQadri|185Sooyetaibajaanaywalo-mushtaqQadri|186Taibakayjaanaywalay-mushtaqQadri|187Tairirehmatonkadarya-mushtaqQadri|188Un_kay_aanay-mushtaqQadri|189Unkimehaknay-mushtaqQadri|190Uthay_haath-mushtaqQadri|191Wah_kiya_baat-mushtaqQadri|192Wah_kiya_joodo_karam-mushtaqQadri|193Wohkamalhusn-mushtaqQadri|194Ya_habeebay_kibriya-mushtaqQadri|195Ya_habeebe_ahmade-mushtaqQadri|196Ya_nabi_salamun_alaika-mushtaqQadri|197Ya_rasoolullahi-mushtaqQadri|198Ya_shafi_al_wara-mushtaqQadri|199Ya-mustafa_ataHo-mushtaqQadri|200Ya-mustafa_ataHoo-mushtaqQadri|201Alvida_alvida_hay|202Chal_qalam|203Ham_bhee_madinay_jaingay|204Sarkaryehnaamtumhara|205Aagaee_mustafa_ki_savari-rashidAzam|206Aaqa_aaqa-rashidAzam|207Dar_pay-rashidAzam|208Jis_nay-rashidAzam|209Main_nazar_karoon-rashidAzam|210Maintopanjatanihoon-rashidAzam|211Maira_dil-rashidAzam|212Maula_ya_salli-rashidAzam|213Meetha_meetha-rashidAzam|214Qaseedaburdasharief-rashidAzam|215Sabsayawalaoalahamranabi-rashidAzam|216Sanu_apnay_kaol-rashidAzam|217Sun_lo-rashidAzam|218Syednekarbalamain-rashidAzam|219Habib-e-khuda-shahid-ul-haqNoori|220Maingadahoon-shahid-ul-haqNoori|221Qasida-e-miraj-shahid-ul-haqNoori|222Rukhdinhay-shahid-ul-haqNoori|223Sabsayawalaoalahamranabi-shahid-ul-haqNoori|224Unkeemehak-shahid-ul-haqNoori|225Zameen-o-zaman-shahid-ul-haqNoori|226Aysabamustafasaykhedayna-siddiqIsmail|227Damane_mustafa-siddiqIsmail|228Dil_main_ho_yaad_tairi-siddiqIsmail|229Gudaze_ishqe_rasool-siddiqIsmail|230Kaaba_mairay_dil_main-siddiqIsmail|231Khaq_sooraj_say-siddiqIsmail|232Koi_saleeqa-siddiqIsmail|233Madeenaykasafr-siddiqIsmail|234Mangtaykhaalihaath-siddiqIsmail|235Mujhkotaibamainbulalo-siddiqIsmail|236Naam_bhi_taira-siddiqIsmail|237Noorimehfil-siddiqIsmail|238Tairaydarkifazaon-siddiqIsmail|239Un_ko_dil_main-siddiqIsmail|240Balaghululaabikamalihi-rehanAttariQadri|241Hardamhomairavird-rehanAttariQadri|242Jitnamairaykhudako-rehanAttariQadri|243Koisaleeqahayaaarzooka-rehanAttariQadri|244Sabsayaolaoaala-rehanAttariQadri|245Sarkar_yeh_nam_tumhara-rehanAttariQadri|246Sarkaryehnaamtumhaara-rehanAttariQadri|247Wohhirabhay-rehanAttariQadri|248Yanabisalaamunalaika-rehanAttariQadri|249Zameenozamaan-rehanAttariQadri", ss=".mp3"},

{n="Naat Collection - Meray Khawja Pia Tahir (27)", l="Urdu", i="meray-khawja-pia-tahir", s="bk_naats_mkhoja", c="naat", d="Aaj ashq meray naat sunain (-).MP3|Aamd e Ramazan hai (-).mp3|Anwaar ki baris mein (Mushtaq).MP3|Barhween Ka Noor Dil Pe Chah Gaya (Ashfaq).mp3|Bhar Do Jholi Meri (Owais).mp3|Faaslon Ko Takkalluf (Tahir).mp3|Hum Faqeer Loog (Tahir).mp3|Kaabay ki Ronaq TRIMMED (Sabih).mp3|Karabaqla kay ja-nisaroon ko salam (Zahid).mp3|Koi mithl Mustafa ka (Mushtaq).MP3|Likh Raha Hoon Naat e Sarwar (Owais).mp3|Me Mar Ki Wi Nahin Marda (Fasih).mp3|MehboobDaMailaHai (Owais).mp3|Naseeb chamkay (Mushtaq).MP3|Pyaray Nabi Jasa Koi Nahi (Husn e Yusuf) (-).mp3|Qabar Jis Dam (Nisar Marfaani).mp3|Qadira Sarwar ARahnuma (336) (Owais).mp3|Qadira Sarwar ARahnuma (583) (Owais).mp3|Qasidah Burdah (Mushtaq).mp3|Sultan e Karbala (Zahid).mp3|Tu nay mansab bhi paya to kiaa (Mushtaq).mp3|Woh Jo Na They ToKuchBhiNaTha (Owais).mp3|Ya Mustafa Ata Ho Phir Izn Hazri Ka (Bilal).mp3|Yaadon Ka Teri Dil Mian Basera (-).mp3|Yeh Arz Gunahgar Ki Hai Shah e Zamana (Bilal).mp3|Zameen Maeli NaHi Hoti (-).mp3|Zindagi Da Maza (Owais).mp3"},

{n="Naatein - Asmatullah Jarar (Khkuly Madeena Album 6)", l="Urdu", i="Khkuly-MADEENA-Album-6", s="bk_naats_khkuly", c="naat", d="1,ALLAH ba darkre pa badla k jannatoona.MP3|10,Munga momenan RABA maen yo sta pa Deen.MP3|11,Pry ravareege la asmana rahmatoona.MP3|12,Stargy me sry d pa zarge dyr na qarar yam.mp3|2,Da sahar bada hyr me nakry pighamoona.MP3|3,Da zra pa kor k me osege.mp3|4,Dyr haseen zama Janan dy khkuly(Rubae).mp3|5,Janan zama janan dy Madani akher zaman.MP3|6,Jannat k khushale da.MP3|7,Kary ye singar dy KHKULY MADEENA.MP3|8,Khaar da MADENY zaka dyr khkuly da.MP3|9,Khkuly nizam da QURAN ghvaram(Mesry).MP3"},

{n="Bayanaat - Faizan-e-Ala Hazrat (183)", l="Urdu", i="BayanatOnFaizan", s="bk_bayan_faizan", c="bayan", d="A Ala Hazart Apnay Zamanay Mein-Faizan e Ala Hazrat 01.09.13|AAlaHazratAurFaizanEFatawaRaziviyaShariff-yaadERaza11.01.12|AAlaHazratAurFanEShayri-mereRaza08.01.12|AAlaHazratAurFatwaRizviya-faizanEAlaHazrat20.01.11|AAlaHazratAurHadaiqEBakshish-blessingsOfAlaHazrat27.08.13|AAlaHazratAurHaqooqUlIbaad-faizanEAlaHazrat25.01.11|AAlaHazratAurIlamEHadees-faizanEAlaHazrat13.01.11|AAlaHazratAurIshqEMadina-razaKiZubanTumhareLiye08.12.13|AAlaHazratAurMuashiyaat-faizanEAlaHazrat16.01.11|AAlaHazratAurNaykiKiDawatAurInfiradiKoosish-faizanEAlaHazrat18.01.11|AAlaHazratAurShokEIlamEDeen-yaadERaza03.01.12|AAlaHazratAurTariqaat-faizanEAlaHazrat16.01.11|AAlaHazratAurTazeemESadaat-yaadERaza07.01.12|AAlaHazratAurUnKeKhulafa-faizanEAlaHazrat11.01.11|AAlaHazratAurUnKiSadgi-faizanEAlaHazrat19.01.11|AAlaHazratAurUnKiShayri-faizanEAlaHazrat10.01.11|AAlaHazratBaHasiyaatEMahirEMayishaat-faizanEAlaHazrat09.12.13|AAlaHazratGareebonKGhamKhar-faizanEAlaHazrat231116|AAlaHazratKIrshadaat-faizanEAlaHazrat171116|AAlaHazratKaFatawaAurShairi-faizanEAlaHazrat211116|AAlaHazratKaHaaj-faizanEAlaHazrat21.01.11|AAlaHazratKaIshqERasool-faizanEAlaHazrat23.01.11|AAlaHazratKaTarjamaKanzUlIman-faizanEAlaHazrat23.01.11|AAlaHazratKeMaktobaat-faizanEAlaHazrat12.01.11|AAlaHazratKeMalfuzaat-faizanEAlaHazrat25.01.11|AAlaHazratKiHadeesPerNazar-faizanEAlaHazrat151116|AAlaHazratKiKaramaat-faizanEAlaHazrat21.01.11|AAlaHazratKiKaramat-faizanEAlaHazrat241116|AAlaHazratKiKhidmatEQurani-faizanEAlaHazrat141116|AAlaHazratKiShairi-faizanEAlaHazrat161116|AAlaHazratKiShaksiyatByMuftiQasim-faizanEAlaHazrat181116|AAlaHazratKiTasaneef-faizanEAlaHazrat27.01.11|AAlaHazratKiZahanat-faizanEAlaHazrat201116|AAlaHazratSeUllamaKiAqidaat-faizanEAlaHazrat221116|ABlessingsOfAlaHazrat07.01.13|AFaizanEAlaHazrat0131.12.12|AFaizanEAlaHazrat0231.12.12|AFaizanEAlaHazrat0331.12.12|AFaizanEAlaHazratEp01221017|AFaizanEAlaHazratEp02231017|AFaizanEAlaHazratEp03241017|AFaizanEAlaHazratEp04251017|AFaizanEAlaHazratEp05261017|AFaizanEAlaHazratEp06271017|AFaizanEAlaHazratEp07291017|AFaizanEAlaHazratEp08301017|AFaizanEAlaHazratEp09011117|AFaizanEAlaHazratEp10011117|AFaizanEAlaHazratEp11021117|AFaizanEAlaHazratEp12031117|AFaizanEAlaHazratEp13051117|AFaizanEAlaHazratEp14071117|AFaizanEAlaHazratEp15071117|AFaizanEAlaHazratEp16081117|AFaizanEAlaHazratEp17091117|AFaizanEAlaHazratEp18101117|AFaizanEAlaHazratEp19121117|AFaizanEAlaHazratEp20131117|AFaizanEAlaHazratEp21141117|AMereRaza02.01.12|AMereRaza06.01.12|AMereRaza07.01.12|AMereRaza09.01.12|AMereRaza11.01.12|AMereRaza12.01.12|AMereRaza13.01.12|AMereRaza14.01.12|AMereRaza16.01.12|AMereRaza18.01.12|ANafsEAmaraSeChutkaraPanayKaMadaniNuska-razaKiZubanTumhareLiye28.12.13|AQablayWiladatAlaHazrat-faizanEAlaHazrat131116|AQuranAurMadhatEMustafa-razaKiZubanTumhareLiye29.12.13|ARazaKiZubanTumhareLiye09.12.13|ATazkiraEImamAhleSunnatImamAhmedRazaKhan28.12.13|AYaadEMadina-mereRaza07.01.12|AYaadERaza02.01.12|AYaadERaza10.01.12|AYaadERaza14.01.12|AYaadERaza17.01.12|BHazratAdamWaHawa-faizanEAmbiyaEp0827.01.11|BHazratHuddAlahisSalaamKeWaqiyat-ambiaIkraamKeWaqiyaat03.12.13|BHazratSayadinaAziz-faizanEAmbiya09.12.10|BHazratSayadinaNooh-faizanEAmbiya01.12.10|BTakhleekEHazratAdam-faizanEAmbiya05.01.11|BTazkiraHazratIssaRuhUlAllah-faizanEAmbiya02.07.10|BTazkiraHazratMusaAlehiSalaam-faizanEAmbiya04.08.10|BTazkiraHazratZikryaAurHazratYahyaAlehiSalaam-faizanEAmbiya02.08.10|CAbdulAllahShahGazi-faizanEAulia01.06.10|CFaqiheAzamAbuAlKhairMuhammadNoorAllahNaeemiQadri01-faizanEAulia14.12.10|CFaqiheAzamAbuAlKhairMuhammadNoorAllahNaeemiQadri02-faizanEAulia21.12.10|CHazoorDataGanjBakashAliHijvari-faizanEAulia25.01.11|CHazoorKhawajaZindaPeer-faizanEAulia03.02.12|CHazoorMuftiEAzamHindMaulanaMustafaRazaKhan-faizanEAulia20.12.10|CHazratAbdulAllahShahGazi-faizanEAulia07.10.10|CHazratBabaFareedUDeenMasoodGanjShakar-faizanEAulia06.11.10|CHazratGazaliEZamaaSyedAhmedKazmi-faizanEAulia02.07.10|CHazratGaziYousafShah-faizanEAulia10.09.10|CHazratMianMuhammadBakash-faizanEAulia29.11.10|CHazratMuhammadShafiBukhariChisti-faizanEAuliaEp8228.12.10|CHazratSakhiShahHussain-faizanEAulia29.11.10|CHazratSardarAhmedQadri-faizanEAulia0102.07.11|CHazratSardarAhmedQadri-faizanEAulia0202.07.11|CHazratSyedDataShahJamalQadriSuharwardi-faizanEAulia11.01.11|CHazratSyedMuhammadAbdulAllahQadriBabaBullayShah-faizanEAulia16.09.10|CKhawajaGareebNawaz-faizanEAulia|CMuftiAhmadYaarKhanNaeemi-faizanEAulia23.09.10|CMuftiEDawatEIslamiMuftiFarooqAttari-faizanEAulia24.12.10|CPeerMehrAliShah-faizanEAulia10.07.10|CPeerSyedJamaatAliShah-faizanEAulia2ndPart0105.10.10|CPeerSyedJamaatAliShah-faizanEAulia2ndPart0205.10.10|CPeerSyedJamaatAliShah-faizanEAuliaPart0127.09.10|CPeerSyedJamaatAliShah-faizanEAuliaPart0227.09.10|CPeerSyedJamaatAliShahLasani-faizanEAulia02.11.10|CPeerSyedYaqoobShahRizvi-faizanEAulia27.10.10|CSheikhUlQuranHazratAbdulGafoorHazarvi-faizanEAuliaEp850118.01.11|CSyedKabirUDinShahDhulaDaryai-faizanEAulia20.10.10|CSyediQutbayMadinaZiaUDeenMadani-faizanEAulia10.11.10|CSyedunaImamAliHaqShaheed-faizanEAulia09.11.10|DFaizanEDruoodOSalaamEp01-shehzadaEAttarBilalAttari09.12.10|DFaizanEDruoodOSalaamEp02-shehzadaEAttarBilalAttari18.12.10|DFaizanEDruoodOSalaamEp03-shehzadaEAttarBilalAttari23.12.10|DFaizanEDruoodOSalaamEp04-shehzadaEAttarBilalAttari30.12.10|DFaizanEDruoodOSalaamEp05-shehzadaEAttarBilalAttari07.01.11|EFaizanEFarzUllomallahKiMakhlukaatMeinGorOFikarEp01290517|EFaizanEFarzUllomilmHasilKarnaFarzHaiEp03310517|EFaizanEFarzUllomnamazMeinKhushuOKhuzuEp05140617|EFaizanEFarzUllomnamazSeekhLijiyeEp02300517|EFaizanEFarzUllomqiraatSeekhLiJiyeEp04130617|FGhusEAzamKaMurdoonKoZindaKarna-faizanEQasidaEGhusiya08.02.14|FGhusEAzamKiKaramaat-faizanEQasidaEGhusiya09.02.14|FGhusEAzamSabWaliyoonKeAfsarHain-faizanEQasidaEGhusiya07.02.14|FGhusEAzamWaliyoonKeSardarHain-faizanEQasidaEGhusiya04.02.14|FPeerPerItraazKarnaManaaHai-faizanEQasidaEGhusiya05.02.14|FSarayAqtaabPerGhusEPaakKiFazilat-faizanEQasidaEGhusiya03.02.14|FShaanEGhusEAzam-faizanEQasidaEGhusiya10.02.14|GHazoorKeAndaazEBayaat-faizanEHadees26.10.11|GHazratSayadinaFarooqEAzam-faizanEHadees06.12.10|GMusalmaanKaMusalmaanSeBartao-faizanEHadees19.11.10|GQurbani-faizanEHadees16.11.10|GSarkarKiBargaMeinHazratJibrailKaAndaazEHaazri-faizanEHadees11.12.11|GTaqwa-faizanEHadees09.10.10|GTuba-faizanEHadees17.09.10|GYazeedIslamAurAhleIslamKiNazarMein-faizanEHadees18.12.11|HFaizanEIlmhazratIbnEAbbasKFazailKaBayaanByMuftiQasimAttariEp111100817|HFaizanEIlmhazratIbnEAbbasKiIlmiQabliyatKAsbaabByMuftiQasimAttariEp113070917|HFaizanEIlmhazratIbnEAbbasKiZahanatKaBayaanByMuftiQasimAttariEp112170817|HFaizanEIlmilmEDeenKHasoolSeMutalikAhmBaatainByMuftiQasimAttariEp114140917|IHabibaEHabibEKhuda-faizanESahabiyaat06.02.12|IHazratAishaKaNaikiKiDawatDeneKaJazba-faizanESahabiyaat15.02.12|IHazratAishaKaZokEIbadaat-faizanESahabiyaat02.01.12|IHazratAishaKeFazail-faizanESahabiyaat09.01.12|IHazratAishaKiSakhawat-faizanESahabiyaat30.01.12|IHazratAishaKiShayri-faizanESahabiyaat16.01.12|IKhatoonEJannatKaIsaarWaSakhwat-faizanESahabiyaat29.09.11|IKhatoonEJannatKaIshqERasool-faizanESahabiyaat17.10.11|IKhatoonEJannatKaWisaalMubarak-faizanESahabiyaat21.11.11|IKhatoonEJannatKaZuhadOQanaat-faizanESahabiyaat07.09.11|IKhatoonEJannatKayFaaqar-faizanESahabiyaat22.09.11|IKhatoonEJannatKayFaaqay-faizanESahabiyaat20.03.11|ISahahabiyaatAurShohrKiKhidmat-sahahabiyaatKeAlaAusaaf02.01.14|ISayedatunaFatimaAurUmvarEKhanadari-faizanESahabiyaat07.07.11|ISayedatunaFatimaKiKaramaat-faizanESahabiyaat30.07.11|ISeraatEHazratRuqiya-sahahabiyaatKeAlaAusaaf03.12.13|IWaqiyaEIfaaq-faizanESahabiyaat22.02.12|IWisaalERasoolParKhatoonEJannatKiQafiyaat-faizanESahabiyaat14.11.11|JHazratAli-faizanESahaba02.12.10|JHazratBilal-faizanESahabaEp1027.01.11|JHazratSayadinaSalmanFarsi-faizanESahabaEp0706.01.11|JHazratSayedatunaUmaeHabiba-faizanESahabaEp0812.01.11|JSeraatEHazratSayedatunaAyeshaSadiqa-faizanESahabaEp0629.12.10|JSeraatEHazratUmar-faizanESahabaEp0923.12.10|JSeraatEHazratUsmaan-faizanESahaba22.12.10|JSeraatESayadinaSaadBinAbiWaqas-faizanESahaba02.02.11|KFaizanEAsharaEMubashara10.11.13|KFaizanEAsharaEMubashara11.11.13|KFaizanEImamHussain021017|KFaizanEMeelad121216|KFaizanEMilaad12RabiUnNoor1435040115|KFaizanEMilaadPashtoZabanMein12RabiUnNoor1436241215|KFaizanEMuftiEAzamHind18.11.13|KFaizanEShahabaOAhlebait13.11.13|KFaizanESubhEBaharan121216|KFaizanESubhEBaharan12RabiUnNoor1436241215", ss=".mp3"},

{n="Duroos-ul-Balagha - Mukammal Urdu Sabaq (91)", l="Urdu", i="Duroos-ul-Balagha_Class_Lectures_in_Urdu_Audio", s="bk_duroos_balagha", c="bayan", d="ContactInformation------1-------------.mp3|ContactInformation------2-------------.mp3|K-A-L-I-M-A-A-T-----------------------.MP3|Sabaq--001-----Ibtida-------19-09-2012.MP3|Sabaq--002-----Ibtida-------22-09-2012.MP3|Sabaq--003-----Ibtida-------23-09-2012.MP3|Sabaq--004---page-015-----24-09-2012.MP3|Sabaq--005---page-015-----25-09-2012.MP3|Sabaq--006---page-015-----26-09-2012.MP3|Sabaq--007---page-016-----27-09-2012.MP3|Sabaq--008---page-017-----29-09-2012.MP3|Sabaq--009---page-018-----30-09-2012.MP3|Sabaq--010---page-019-----01-10-2012.MP3|Sabaq--011---page-019-----02-10-2012.MP3|Sabaq--012---page-020-----03-10-2012.MP3|Sabaq--013---page-020-----04-10-2012.MP3|Sabaq--014---page-021-----06-10-2012.MP3|Sabaq--015---page-022-----07-10-2012.MP3|Sabaq--016---page-022-----08-10-2012.MP3|Sabaq--017---page-023-----10-10-2012.MP3|Sabaq--018---page-024-----11-10-2012.MP3|Sabaq--019---page-025-----13-10-2012.MP3|Sabaq--020---page-025-----14-10-2012.MP3|Sabaq--021---page-025-----15-10-2012.MP3|Sabaq--022---page-025-----16-10-2012.MP3|Sabaq--023---page-025-----17-10-2012.MP3|Sabaq--024---page-026-----18-10-2012.MP3|Sabaq--025---page-027-----04-11-2012.MP3|Sabaq--026---page-029-----05-11-2012.MP3|Sabaq--027---page-030-----06-11-2012.MP3|Sabaq--028---page-032-----07-11-2012.MP3|Sabaq--029---page-033-----08-11-2012.MP3|Sabaq--030---page-034-----13-11-2012.MP3|Sabaq--031---page-035-----14-11-2012.MP3|Sabaq--032---page-037-----15-11-2012.MP3|Sabaq--033---page-039-----17-11-2012.MP3|Sabaq--034---page-040-----20-11-2012.MP3|Sabaq--035---page-043-----21-11-2012.MP3|Sabaq--036---page-043-----22-11-2012.MP3|Sabaq--037---page-045-----26-11-2012.MP3|Sabaq--038---page-046-----27-11-2012.MP3|Sabaq--039---page-047-----01-12-2012.MP3|Sabaq--040---page-049-----02-12-2012.MP3|Sabaq--041---page-051-----04-12-2012.MP3|Sabaq--042---page-052-----05-12-2012.MP3|Sabaq--043---page-053-----06-12-2012.MP3|Sabaq--044---page-055-----08-12-2012.MP3|Sabaq--045---page-056-----10-12-2012.MP3|Sabaq--046---page-056-----11-12-2012.MP3|Sabaq--047---page-058-----13-12-2012.MP3|Sabaq--048---page-059-----16-12-2012.MP3|Sabaq--049---page-061-----17-12-2012.MP3|Sabaq--050---page-062-----22-12-2012.MP3|Sabaq--051---page-063-----23-12-2012.MP3|Sabaq--052---page-065-----24-12-2012.MP3|Sabaq--053---page-067-----29-12-2012.MP3|Sabaq--054---page-067-----30-12-2012.MP3|Sabaq--055---page-068-----31-12-2012.MP3|Sabaq--056---page-071-----01-01-2013.MP3|Sabaq--057---page-072-----05-01-2013.MP3|Sabaq--058---page-074-----06-01-2013.MP3|Sabaq--059---page-076-----08-01-2013.MP3|Sabaq--060---page-078-----09-01-2013.MP3|Sabaq--061---page-080-----10-01-2013.MP3|Sabaq--062---page-083-----13-01-2013.MP3|Sabaq--063---page-084-----14-01-2013.MP3|Sabaq--064---page-087-----15-01-2013.MP3|Sabaq--065---page-089-----16-01-2013.MP3|Sabaq--066---page-093-----19-01-2013.MP3|Sabaq--067---page-098-----20-01-2013.MP3|Sabaq--068---page-103-----21-01-2013.MP3|Sabaq--069---page-105-----22-01-2013.MP3|Sabaq--070---page-108-----23-01-2013.MP3|Sabaq--071---page-109-----24-01-2013.MP3|Sabaq--072---page-111-----26-01-2013.MP3|Sabaq--073---page-113-----27-01-2013.MP3|Sabaq--074---page-115-----28-01-2013.MP3|Sabaq--075---page-118-----29-01-2013.MP3|Sabaq--076---page-121-----30-01-2013.MP3|Sabaq--077---page-123-----31-01-2013.MP3|Sabaq--078---page-125-----03-02-2013.MP3|Sabaq--079---page-127-----18-02-2013.MP3|Sabaq--080---page-129-----20-02-2013.MP3|Sabaq--081---page-130-----21-02-2013.MP3|Sabaq--082---page-133-----24-02-2013.MP3|Sabaq--083---page-136-----25-02-2013.MP3|Sabaq--084---page-139-----26-02-2013.MP3|Sabaq--085---page-141-----27-02-2013.MP3|Sabaq--086---page-144-----28-02-2013.MP3|Sabaq--087---page-147-----02-03-2013.MP3|Sabaq--088---page-149-----04-03-2013.MP3"},

{n="Bayanat - Mufti Muhammad Arshad (Kowloon Masjid, 61)", l="Urdu", i="MAMMuftiMUHAMMADARSHADKOWLOONMASJIDHONGKONG", s="bk_bayan_arshad", c="bayan", d="1-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|10-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|100 Sal ki Moot.MP3|11-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|12-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|13-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|14-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|15-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|16-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|17-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|18-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|19-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|2-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|20-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|21-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|22-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|23-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|24-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|25-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|26-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|27-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|28-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|29-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|3-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|30-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|31-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|32-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|33-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG (2).MP3|34-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|35-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|36-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|37-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|38-FINAL PROPHETWOOD - URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|39-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|4-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|40-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|41-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|42-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|43-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|5-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|6-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|7-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|8-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|9-URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|ABOUT MOHABAT - URDU&ENGLISH BAYAN-BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|Ahliah kai Haqooq  - BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.mp3|Aitedal  - BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|Akhalq Mustafa SAWS- BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|Akhlaq - BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|Akhlaq Rasool SAWS- BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.mp3|Al-e- Imran V 12 - BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.mp3|Brotherhood - BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|Dawat kai Usool- BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|Dawat main Mushkilat - BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|HAZARTH ABUBACKE - 2 BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|HAZARTH ABUBACKE - BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|Hazrat Hussain - BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|Hilm - BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|Itiba e Rasool - BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|Jannat - BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.MP3|Kamyabi - BY IMAM Mufti MUHAMMAD ARSHAD,KOWLOON MASJID  HONG KONG.mp3"},

{n="Bayanaat - Ala Hazrat.net (29)", l="Urdu", i="AlaHazrat.netBayanat", s="bk_bayan_alahazrat", c="bayan", d="01Aadaabe_mehfil|02Amaanat|03Aurat_ka_kirdar|04Hafize_millat|05Ilm_ki_ehmiyat|06Iman_ki_jaan|07Milad_ka_suboot|08Moat|09Mushkil_kusha|10Namaaz_kay_faiday|11Nikah|12Sahaba_ka_aqeedah|13IlmiMuzakra|14Qirat|15Naat|16Speech|17Qaseedah|18Manajat|19Dua|20Salam|21SpeechAurNaat|22Manazra01|23Manazra02|24Manazra03|25Manazra04|26Manazra05|27Manazra06|28Manazra08|29Manazra07", ss=".mp3"},

{n="Jadu ki Haqeeqat - Bint A. Shakoor (36)", l="Urdu", i="jadu-ki-haqeeqat-by-bint-a.-shakoor-as-saajidoon", s="bk_jadu_haqeeqat", c="bayan", d="01. Jadu ki Haqeeqat Part-01 Introduction by Bint A.Shakoor|02. Jadugar aur showbdebaaz may farq by Bint A.Shakoor|03. Jadugar ki pahchaan-1 (maa kaa naam poochega) by Bint A.Shakoor|04. Jadugar ki pahchaan-2: Jadugar kon konsi chizen maangtaa hai? by Bint A.Shakoor|05. Jadugar ki pahchaan-3 Jadugar kya padhta hai? by Bint A.Shakoor|06. Jadugar ki pahchaan-4 Jadugar kon konsi chizen detaa hai? by Bint A.Shakoor|07. Showdebaaz ki pahchaan-1 Showbdebaaz ke titles by Bint A.Shakoor|09. Showdebaaz ki pahchaan-3 Showbdebaaz munh yaa naak se aag kaise nikalte hain? by Bint A.Shakoor|10. Showdebaaz ki pahchaan-4 Showbdebaaz payaley (bowl) may garmi kaise paida karta hai! by Bint A.Shakoor|11. Showdebaaz ki pahchaan-5 Showbdebaaz ande ke andar se kuch chizen kaise nikalta hai! by Bint A.Shakoor|12. Showdebaaz ki pahchaan-6 Showbdebaaz rumal yaa kameez se kuch chizen kaise nikalta hai! by Bint A.Shakoor|13. Jadu kerne ke wajuhaat! by Bint A.Shakoor|14. Jadugar ko mareez ka maazi kaise pata chalta hai? by Bint A.Shakoor|15. Qareen se mutaliq chand waqiat! by Bint A.Shakoor|16. Jadugar ke gaybi ilm ka d'awaa! by Bint A.Shakoor|17. Jadu ke alaamaat 1-10 by Bint A.Shakoor|18. Jadu ke alaamaat 11-19 by Bint A.Shakoor|19. Muhabbat, nafrat, bimari aur qatal ka jadu by Bint A.Shakoor|20. Jadugar khud kya kerte hain aur logon ko kya kerne kahte  hain by Bint A.Shakoor|21. Jadu se ehtiyaat Part-1 (1-5) by Bint A.Shakoor|22. Jadu se ehtiyaat Part-2 (6-10) by Bint A.Shakoor|23. Jadu se ehtiyaat Part-3 (11-15) by Bint A.Shakoor|24. Jadu se ehtiyaat Part-4 (16-20) by Bint A.Shakoor|25. Jadu se ehtiyaat Part-5 (21-25) by Bint A.Shakoor|26. Jadu se ehtiyaat Part-6 (26-30) by Bint A.Shakoor|27. Jadu ka ilaaj Part-1 by Bint A.Shakoor|28. Jadu ka ilaaj Part-2 by Bint A.Shakoor|29. Jadu ka ilaaj Part-3 (Ruqyah Shariah pdf) by Bint A.Shakoor|30. Jadu ka ilaaj Part-4 (Ruqyah Shariah pdf) by Bint A.Shakoor|31. Jadu ka ilaaj Part-5 (Ruqyah Shariah from Ahaadith or Sunnah) by Bint A.Shakoor|32. Jadu ka ilaaj Part-6 (Ruqyah Shariah from Sunnah pdf) by Bint A.Shakoor|33. Nazar-e-bad ka ilaaj by Bint A.Shakoor|34. Sachcha Waqia by Special Guest Firdous Sultana|35. Sachcha Waqia by Special Guest Nafeesa|36. As-saajidoon Social Media|38. Feedback on Ruqyah Compiled by Bint A.Shakoor", ss=".mp3"},

{n="Tafseer Ahsanul Bayan (Urdu) - Mukammal Audio (247 Bayanat)", l="Urdu", i="1-alfatiha", s="bk_urdu_ahsanul", d="1 Alfatiha.mp3|2 Albaqarah.mp3|3 Albaqarah.mp3|4 Albaqarah.mp3|5 Albaqarah.mp3|6 Albaqarah.mp3|7 Albaqarah.mp3|8 Albaqarah.mp3|9 Albaqarah.mp3|10 Albaqarah.mp3|11 Albaqarah.mp3|12 Albaqarah.mp3|13 Albaqarah.mp3|14 Albaqarah.mp3|15 Albaqarah.mp3|16 Albaqarah.mp3|17 Albaqarah.mp3|18 Albaqarah.mp3|19 Albaqarah.mp3|20 Albaqarah & Aal Imran.mp3|21 Aal Imran.mp3|22 Aal Imran.mp3|23 Aal Imran.mp3|24 Aal Imran.mp3|25 Aal Imran.mp3|26 aal imran.mp3|27 aal imran.mp3|28 Aal Imran.mp3|29 Aal Imran.mp3|30 Aal Imran.mp3|31 Aal Imran & Annisa.mp3|32 Annisa.mp3|33 Annisa.mp3|34 Annisa.mp3|35 Annisa.mp3|36 Annisa.mp3|37 Annisa.mp3|38 Annisa.mp3|39 Annisa.mp3|40 Annisa.mp3|41 Annisa.mp3|42 Annisa.mp3|43 Annisa & Almaidah.mp3|44 Almaidah.mp3|45 Almaidah.mp3|46 Almaidah.mp3|47 Almaidah.mp3|48 Almaidah.mp3|49 Almaidah.mp3|50 Almaidah.mp3|51 Almaidah.mp3|52 Almaidah & Alanaam.mp3|53 Alanaam.mp3|54 Alanaam.mp3|55 Alanaam.mp3|56 Alanaam.mp3|57 Alanaam.mp3|58 Alanaam.mp3|59 Alanaam.mp3|60 Alanaam.mp3|61 Alanaam & Alaaraf.mp3|62 Alaaraf.mp3|63 Alaaraf.mp3|64 Alaaraf.mp3|65 Alaaraf.mp3|66 Alaaraf.mp3|67 Alaaraf.mp3|68 Alaaraf.mp3|69 Alaaraf.mp3|70 Alaaraf.mp3|71 Alaaraf.mp3|72 Alaaraf & Alanfal.mp3|73 Alanfal.mp3|74 alanfal.mp3|75 Alanfal.mp3|76 Alanfal & Attawbah.mp3|77 Attawbah.mp3|78 Attawbah.mp3|79 Attawbah.mp3|80 Attawbah.mp3|81 Attawbah.mp3|82 Attawbah.mp3|83 Attawbah.mp3|84 Attawbah & Younus.mp3|85 Younus.mp3|86 Younus.mp3|87 Younus.mp3|88 Younus.mp3|89 Younus.mp3|90 Younus & Hood.mp3|91 Hood.mp3|92 hood.mp3|93 Hood.mp3|94 Hood.mp3|95 Hood.mp3|96 Yousuf.mp3|97 Yousuf.mp3|98 Yousuf.mp3|99 Yousuf.mp3|100 Yousuf.mp3|101 Yousuf & Raad.mp3|102 Raad.mp3|103 Raad & Ibrahim.mp3|104 Ibrahim.mp3|105 Ibrahim.mp3|106 Ibrahim & Hijr.mp3|107 Hijr.mp3|108 Hijr & Nahl.mp3|109 Nahl.mp3|110 Nahl.mp3|111 Nahl.mp3|112 Nahl.mp3|113 Nahl.mp3|114 Israa.mp3|115 Israa.mp3|116 Israa.mp3|117 Israa.mp3|118 Israa & Kahf.mp3|119 Kahf.mp3|120 Kahf.mp3|121 Kahf.mp3|122 Kahf.mp3|123 Kahf & Mariam.mp3|124 Mariam.mp3|125 Mariam.mp3|126 Mariam & Taha.mp3|127 Taha.mp3|128 Taha.mp3|129 Taha.mp3|130 Taha & Alanbiaa.mp3|131 Alanbiaa.mp3|132 Alanbiaa.mp3|133 Alanbiaa.mp3|134 Alanbiaa & Alhajj.mp3|135 Alhajj.mp3|136 Alhajj.mp3|137 Alhajj.mp3|138 Alhajj & Almominon.mp3|139 Almominon.mp3|140 Almominon.mp3|141 Almomonon & Annoor.mp3|142 Annoor.mp3|143 Annoor.mp3|144 Annoor.mp3|145 Annoor.mp3|146 Annoor & Alfurqan.mp3|147 Alfurqan.mp3|148 Alfurqan & Ashuaraa.mp3|149 Ashuaraa.mp3|150 Ashuaraa.mp3|151 Ashuaraa.mp3|152 Asuaraa & Annaml.mp3|153 Annaml.mp3|154 Annaml.mp3|155 Annaml.mp3|156 Annaml & Alqasas.mp3|157 Alqasas.mp3|158 Alqasas.mp3|159 Alqasas.mp3|160 Alqasas & Alankaboot.mp3|161 Alankaboot.mp3|162 Alankaboot.mp3|163 Alankaboot & Arroom.mp3|164 Arroom.mp3|165 Arroom.mp3|166 arroom & luqman.mp3|167 Luqman.mp3|168 Assajdah.mp3|169 Alahzab.mp3|170 Alahzab.mp3|171 Alahzab.mp3|172 Alahzab.mp3|173 Alahzab & Saba.mp3|174 Saba.mp3|175 Saba.mp3|176 Saba & Fatir.mp3|177 Fatir.mp3|178 Fatir & Yaseen.mp3|179 Yaseen.mp3|180 Yaseen.mp3|181 Assaffat.mp3|182 Assaffat.mp3|183 Assaffat & Saad.mp3|184 Saad.mp3|185 Saad.mp3|186 Saad & Azzumar.mp3|187 Azzumar.mp3|188 Azzumar.mp3|189 Azzumar & Ghafir.mp3|190 Ghafir.mp3|191 Ghafir.mp3|192 Ghafir.mp3|193 Ghafir & Fussilat.mp3|194 Fussilat.mp3|195 Fussilat & Ashura.mp3|196 Ashura.mp3|197 Ashura.mp3|198 Ashura & Azzukhruf.mp3|199 Azzukhruf.mp3|200 Azzukhruf & Addukhan.mp3|201 Addukhan.mp3|202 Addukhan & Aljathiah.mp3|203 Aljathiah & Alahqaf.mp3|204 Alahqaf.mp3|205 Alahqaf & Muhammad.mp3|206 Muhammad.mp3|207 Alfath.mp3|208 Alfath.mp3|209 Alhujurat & Qaaf.mp3|210 Qaaf.mp3|211 Azzariat.mp3|212 Azzariat & Attor.mp3|213 Attor & Annajm.mp3|214 Annajm & Alqamar.mp3|215 Alqamar.mp3|216 Arrahman.mp3|217 Arrahman & Alwaqiah.mp3|218 Alwaqiah & Alhadeed.mp3|219 Alhadeed.mp3|220 Alhadeed & Almujadalah.mp3|221 Almujadalah & Alhashr.mp3|222 Alhashr.mp3|223 Alhashr & Almumtahinah.mp3|224 Almumtahinah & Assaff.mp3|225 Aljumuah & Almunafiqoon.mp3|226 Attaghabun.mp3|227 Attalaq & Attahreem.mp3|228 Attahreem & Almulk.mp3|229 Almulk & Alqalam.mp3|230 Alqalam & Alhaqqah.mp3|231 Alhaqqah & Almaarij.mp3|232 Almaarij & Nooh.mp3|233 Aljinn.mp3|234 Almuzzammil & Almuddassir.mp3|235 Almuddassir & Alqiamah.mp3|236 Alinsan & Almursalat.mp3|237 Almursalat & Annaba'.mp3|238 Annaba' & Annaziat.mp3|239 Abas & Attakweer & Alinfitar.mp3|240 Alinfitar & Almutaffifeen & Alinshiqaq.mp3|241 Alinshiqaq & Alburooj & Attariq.mp3|242 Alaala & Alghashiah & Alfajr.mp3|243 Alfajr & Albalad & Asshams & Allail.mp3|244 Adduha & Assharh & Atteen & Alalaq.mp3|245 Alqadr & Albayinah & Azzilzal & Alaadiat.mp3|246 Alqariah To Quraish.mp3|247 Almaoon To Annas.mp3"},
{n="Khulasa Quran - Para-wise Short Tafseer (Bint A. Shakoor, 30 Paras)", l="Urdu", i="khulasa-quran-short-tafseer-in-urdu-hindi-by-bint-a.shakoor-2022", s="bk_urdu_khulasa", p="Khulasa Quran Para-%02d by Bint A.Shakoor 2022.mp3", nf=30},
{n="Zikr-e-Khair (Book of the Beloved) - Shaykh Mahboob Alam Saidavi (26)", l="Urdu", i="Zikr-e-khairOrBookOfTheBelovedUrduByShaykhMahboobAlamSaidavi", s="bk_urdu_zikr", d="00-IntroductionToTheAudioBookOfZikr-e-khairKnownAsSahefa-e-mahboobOrBookOfTheBeloved.mp3|00-WhatIsThePurposeOfLifeAndEternalBlissAndWhyItIsImportantToStriveForIt.mp3|01-BookOfTheBeloved-IntroductionOfAuthorShaykhMahboobAlamSaidaviByMuhammadAhmadHashimi.mp3|02-BookOfTheBeloved-IntroductionOfTheBookByAuthorShaykhMahboobAlamSaidavi.mp3|03-BookOfTheBeloved-IntroductionInPoem.mp3|04-BookOfTheBeloved-Chapter1-OuterAppearanceAndEarlyLifeOfShaykhTawakkulShah.mp3|05-BookOfTheBeloved-Chapter2-TrustInGod-CondemnationOfWorldliness-EarningAPermissibleLivelihood.mp3|06-BookOfTheBeloved-Chapter2-TrustInGod-ProtectingOneselfFromExcessiveIndulgenceInWorldliness-AdviceForOuterPractitionersOfSpirituality-GratitudeAndContentment.mp3|07-BookOfTheBeloved-Chapter2-TrustInGod-WaysOfInculcatingTrustInGodEspeciallyInTheLightOfQuranAndTheNobleWayOfProphetMuhammadPeaceBeUponHim.mp3|08-BookOfTheBeloved-Chapter3-ObeyingTheDivineCommandments-RealMeaningOfSayingsOfSaints-MixingWithPeopleWithCare-EtiquettesOfSaints-BeautifulConduct-GuidingPeople.mp3|09-BookOfTheBeloved-Chapter3-ObeyingTheDivineCommandments-FollowingTheNobleWayOfProphetMuhammadPeaceBeUponHim.mp3|10-BookOfTheBeloved-Chapter4-IssuesOfTheSpiritualPath-DangersOfThePathAndCondemnationOfTheLowerSelf-Repentance-RightsOfSpiritualGuideAndSeekerOfTruth.mp3|11-BookOfTheBeloved-Chapter4-LovingAndVistingTheProphetAndHisLifeAfterDeath-ImaginingTheSpiritualGuideAndHisCompany-SincerityPerseveranceAndSpiritualEcstasy-AltruismAndHumility.mp3|12-BookOfTheBeloved-Chapter4-IssuesOfTheSpiritualPath-Altruism-SpiritualStruggleDivineRemembranceSpiritualContemplationDeepSpiritualAbsorptionReturnJourneyToOnesRealCountry.mp3|13-BookOfTheBeloved-Chapter4-IssuesOfTheSpiritualPath-PrayersAndSendingBlessingsAndSalutationsOnProphet-LoveOfVisionOfGodAcceptanceAndAgreementWithActionsOfGod-meetingAndSeeingGod.mp3|14-BookOfTheBeloved-Chapter4-IssuesOfTheSpiritualPath-MiscellaeneousSpiritualMattersAndTheirExplanations.mp3|15-BookOfTheBeloved-Chapter5-KnowledgeTaughtDirectlyByGod-SendingBlessingsOnDeceasedThroughFatiha-FollowingRecognizedAuthoritiesInReligiousKnowledge-KnowledgePutInHeartDirectlyByGod.mp3|16-BookOfTheBeloved-Chapter6-KamalatOrExcellences-MeetingWithJinns-MeetingWithAbdalOrSaintsOfHighestCalibre-SpiritualUnveilings.mp3|17-BookOfTheBeloved-Chapter6-KamalatOrExcellences-MiraclesAndGuardingTheSpeech.mp3|18-BookOfTheBeloved-Chapter6-KamalatOrExcellences-SpiritualPowersToMakeChangesAndSpiritualStations-ComparisonWithOtherSaintsAndDivineAcceptanceFromTheVeryBeginning.mp3|19-BookOfTheBeloved-Chapter6-KamalatOrExcellences-OnenessOfGodAndDominationOfBelongingToASpiritualTraditionAndCompletionOfSpiritualExcellence.mp3|20-BookOfTheBeloved-Chapter7-ConditionOfShaykhTawakkulShahAtTheEndOfHisLife-DeathOfShaykhTawakkulShah-MiscellaneousTopicsRelatedToTheLifeOfTheShaykh.mp3|21-BookOfTheBeloved-Chapter8-DailySpiritualRoutines-CommonRoutines-RoutinesRegardingBeingConsciousOfDeepMeanings.mp3|22-BookOfTheBeloved-Chapter8-DailySpiritualRoutines-RoutinesRegardingBeingConsciousOfDeepMeaningsContinued.mp3|23-BookOfTheBeloved-EndOfTheBook-EulogyInArabicPersianAndUrduPoetryByMaulviHaneefAliRu-abQuraishiAboutShaykhTawakkulAuthorMahboobAlamSaidaviAndHisBook.mp3|24-BookOfTheBeloved-EndOfTheBook-ConcludingRemarksAboutAuthorShaykhMahboobAlamSaidaviAndHisBookAndBriefDescriptionOfSomeOtherRelevantBooksByHisStudentMuhammadAhmadHashimi.mp3"},
{n="Madinah Arabic Book 1 - Urdu Shaheeh (Dr. V. Abdur Rahim, 23 Sabaq)", l="Urdu", i="MAA_BK1_ARS", s="bk_urdu_madina1", p="MAA_BK1_ARS_L%02d.mp3", nf=23},
{n="Madinah Arabic Book 2 - Urdu Shaheeh (31 Sabaq)", l="Urdu", i="MAA_BK2_ARS", s="bk_urdu_madina2", p="MAA_BK2_ARS_L%02d.mp3", nf=31},
{n="Madinah Arabic Book 3 - Urdu Shaheeh (28 Sabaq)", l="Urdu", i="MAABK3ARSL18", s="bk_urdu_madina3", p="MAA_BK3_ARS_L%02d.mp3", nf=28},
{n="Hazrat Umar Farooq (RA) - Mukammal 60 Episoad (Elhaan)", l="Urdu", i="hazrat-umar-farooq-ep-26", s="bk_urdu_umar60", d="New folder/Hazrat Umar Farooq Ep01   Jab Nabi Pak Hazrat Muhammad (PBUH) Ko Zeher Dia Gaya   Elhaan.mp3|New folder/Hazrat Umar Farooq Ep02   Hazrat Umar (RA) Ki Khilafat Ki Mukhalifat Kyun Ki Gayi   Elhaan.mp3|New folder/Hazrat Umar Farooq Ep03 _ Nabi Pak (PBUH) Ka Yahoodion Ke Sath Agreement _ Elhaan(MP3_160K)_1.mp3|New folder/Hazrat Umar Farooq Ep04   Hazrat Umar (RA) Ki Jagah Hazrat Ali (RA) Ko Salar Banana   Elhaan.mp3|New folder/Hazrat Umar Farooq Ep05 _ Jang Mai Pakri Gayi Aurat Aur Uski Beti Ki Dastaan _ Elhaan(MP3_128K).mp3|New folder/Hazrat Umar Farooq Ep06   Hazrat Zubair (RA) Aur Unki Londi Ki Kahani   Elhaan.mp3|New folder/Hazrat Umar Farooq Ep07   Hazrat Khalid Bin Waleed Ko Salar Se Hatane Ka Qissa   Elhaan.mp3|New folder/Hazrat Umar Farooq Ep08 .mp3|New folder/Hazrat Umar Farooq Ep09 _ Umme Zimal Salma Kon Thi Aur Nabi Pak PBUH Ke Khilaf Jang Kyun Ki _ Elhaan(MP3_128K).mp3|New folder/Hazrat Umar Farooq Ep10   Kisra Pervez Ki Batameezi Aur Uska Anjaam   Elhaan.mp3|New folder/Hazrat Umar Farooq Ep11 _ Faras Ke Kafir Aur Musalmano Ki Choti Si Fauj _ Elhaan(MP3_128K).mp3|New folder/Hazrat Umar Farooq Ep12 _ Apne Hi Khawand Ko Shadi Ki Rat Qatal Karne Wali Aurat _ Elhaan(MP3_128K).mp3|New folder/Hazrat Umar Farooq Ep13 _ Kafiron Ke Naak Mai Dam Karne Wale Hazrat Abu Obaida RA _ Elhaan(MP3_128K).mp3|New folder/Hazrat Umar Farooq Ep14 _  Musanna Bin Harisa Aur Kafiron Ki Jang _ Elhaan(MP3_128K).mp3|New folder/Hazrat Umar Farooq Ep15 _ Iran (Faras) aur Musalmano Ki Tareekhi Jang _ Elhaan(MP3_128K).mp3|New folder/Hazrat Umar Farooq Ep16 _ Hazrat Khalid Bin Waleed RA Se Kufaar Ki Shikast _ Elhaan(MP3_128K).mp3|New folder/Hazrat Umar Farooq Ep17 _ Wo Jang Jis Mai Musalmano Ke 8 Salaar Shaheed Hue _ Elhaan(MP3_128K).mp3|New folder/Hazrat Umar Farooq Ep18 _ Jab Faris Ki Fauj Ne Apni Auraton Par Hamla Kar Dia _ Elhaan(MP3_128K).mp3|New folder/Hazrat Umar Farooq Ep19 _ Faras Ka Beghairat Badshah Aur Musalmano Ka Qeher _ Elhaan(MP3_128K).mp3|New folder/Hazrat Umar Farooq Ep20   Jang Se Bhagne Walon Ke Liye Hazrat Umar RA Ka Farman   ELhaan.mp3|New folder/Hazrat Umar Farooq Ep21   Hazrat Musanna Bin Harisa Ke Jism Par Zakham Aur Jang Ka Medaan   Elhaan.mp3|New folder/Hazrat Umar Farooq Ep22   Faras Ke Sipah Salar Ko Khatam Karne Wala Sipahi   Elhaan.mp3|New folder/Hazrat Umar Farooq Ep23   Jab Faras Ke Kafiron Ka Samna Musalmano Ke Sath Hua   Elhaan.mp3|New folder/Hazrat Umar Farooq Ep24   Jab Christians Ne Musanna Bin Harisa Ki Help Ki   Elhaan.mp3|New folder/Hazrat Umar Farooq Ep25   Khusro Parvez Jis Ne Nabi Pak PBUH Ko Giraftar Karne Ka Hukam Dia   Elhaan.mp3|New folder/Hazrat Umar Farooq Ep26 .mp3|New folder/Hazrat Umar Farooq Ep27   Hazrat Umar RA Ka Hazrat Ali RA Ko Salaar Select Karna   Elhaan.mp3|New folder/Hazrat Umar Farooq Ep28   hazrat Umar Ka Kafiron Ke Khilaf Elan e Jang   Elhaan.mp3|New folder/Hazrat Umar Farooq Ep29   Shahi Khandan Ki Beti Aur Uska Aik Musician Se Pyar   Kaavish.mp3|New folder/Hazrat Umar Farooq Ep30   Hazrat Umar RA Ki Fauj Aur Faras Ka Badbakht Badshah   Kaavish.mp3|New folder/Hazrat Umar Farooq Ep31   Faris Ka Taqatwar Salar Rustam Musalmano Kay Agay Bay Bus   Kaavish.mp3|New folder/Hazrat Umar Farooq Ep32   Hazrat Umar Kay Dour Ka Mashoor Commando Mission   Kaavish.mp3|New folder/Hazrat Umar Farooq Ep33   Rustam Kay Darbar Main Islami Lashkar Ka Numainda   Kaavish.mp3|New folder/Hazrat Umar Farooq Ep34   Jab Musalmanon Kay Lashkar Main Yahoodi Jasoos Ghus Gaey   Kaavish.mp3|New folder/Hazrat Umar Farooq Ep35.mp3|New folder/Hazrat Umar Farooq Ep36   Mast hathion ka Islami Lashkar Per Hamla   Kaavish.mp3|New folder/Hazrat Umar Farooq Ep37  Jung E Qadsia Ka Sab Say Mashoor Aur Khoon Raiz Muqabla   Kaavish.mp3|New folder/Hazrat Umar Farooq Ep38   Hazrat Saad Bin Abi Waqas Ka Ghora Chori Kernay Wala Mujahid   Kaavish.mp3|New folder/Hazrat Umar Farooq Ep39   Jung E Qadisa Main Musalman Aurton Ka Kirdar   Kaavish.mp3|New folder/Hazrat Umar Farooq Ep40   Rustam Ka Saad Bin Abi Waqas Per Shab Khoon   Kaavish.mp3|New folder/Hazrat Umar Farooq Ep41   Farsi Lashkar Ka fajay Kay Waqt Achanak Hamla   Kaavish.mp3|New folder/Hazrat Umar Farooq Ep42   Jung E Qadsia Ka Akhri Roz Aur Rustam Ki Mout   Kaavish.mp3|New folder/Hazrat Umar Farooq Ep43   Jung E Qadsia Main Lernay Walay Mujahidon Ki Bahaduri Ka Tazkra   kaavish.mp3|New folder/Hazrat Umar Farooq Ep44   Yahoodi Aur Farsi Musalmanon Kay Khilaf Aik Ho Gaey   Kaavish.mp3|New folder/Hazrat Umar Farooq Ep45   Hazrat Umar RA Ka Madain Per Hamla Kernay Ka Hukm   Kaavish.mp3|New folder/Hazrat Umar Farooq Ep46   Farsion Ka Islami Lashkar Per Khonwar Shair Say Hamla   Kaavish.mp3|New folder/Hazrat Umar Farooq Ep47   Musalman Lashkar Per Yahoodi Rahib Kay Jadu Ki Dastan   Kaavish.mp3|New folder/Hazrat Umar Farooq Ep48   Gustakh E Rasool Qisra  Ki Saltanat Musalmanon Kay Qadmon Main   Kaavish.mp3|New folder/Hazrat Umar Farooq Ep49   Jab Yahoodi Rahib Nay Aik No moloud Bachay Ki Qurbani Di   Kaavish.mp3|New folder/Hazrat Umar Farooq Ep50   Hazrat Umar Ka Shehr Per Poori Taqat Say Hamla  Ka Hukam   Kaavish.mp3|New folder/Hazrat Umar Farooq Ep51   Yazdgar Ka Adhay Faris Kay Badlay Hathyar Dalnay Ka Ailan   Kaavish.mp3|New folder/Hazrat Umar Farooq Ep52   River Dajla Mai Ghoray Doraane Ka Waqia   Kaavish.mp3|New folder/Hazrat Umar Farooq Ep53   Madain Kay Mehel Per Musalmano Ka Qabza   Kaavish.mp3|New folder/Hazrat Umar Farooq Ep54   Jab Kisra Kay Kangan Suraqa Ko Pehnae Gaey   Kaavish.mp3|New folder/Hazrat Umar Farooq Ep55  Farsi Lashkar Ka Jalola Main Jama Ho Ker Shadeed Hamla   Kaavish.mp3|New folder/Hazrat Umar Farooq Ep56   Jalolah Ki Fatah Aur Atish Paraston Ki Shikast   Kaavish.mp3|New folder/Hazrat Umar Farooq Ep57   Hazrat Umar Ka Jalola Ki Fatah Per Jazbati Khitab   Kaavish.mp3|New folder/Hazrat Umar Farooq Ep58   Jab Musalmanon Nay Qisra Ki Gustakhi Ka Badla Liya   Kaavish.mp3|New folder/Hazrat Umar Farooq Ep59   Farsi Fouj Apnay Akhri Sheher Ko Bhe Khali Chor Gai   Kaavish.mp3|New folder/Hazrat Umar Farooq Ep60 (Final Episode)   Bachay Khuchay Farsi aur Romi Daston Ka Khatma    kaavish.mp3"},
{n="Daur-e-Quran Tafseer Course - Hafiz Naveed Ahmed (74 Dars)", l="Urdu", i="HowToMakeTheBestOutOfThisTafseerCourse", s="bk_urdu_darse74", d="000bIntroductionToDauraEQuran-HafizNaveedAhmed.mp3|001-Fatiha-alBaqara07.mp3|002-AlBaqara08-32.mp3|003-AlBaqara33-61.mp3|004-Al-baqarah62-82.mp3|005-Al-baqarah83-103.mp3|006-Al-baqarah104-137.mp3|007-Al-baqara138-167.mp3|008-AlBaqara168186.mp3|009-Al-baqara187207.mp3|010-AlBaqara208221.mp3|011-AlBaqara222237.mp3|012-AlBaqara238260.mp3|013-AlBaqara261281.mp3|014-AlBaqara282AlImran14.mp3|015-AlImran1554online-audio-converter.com.mp3|016-AlImran5578online-audio-converter.com1.mp3|017-AlImran79120online-audio-converter.com.mp3|17-april-18QuranKeHuqooq.mp3|018-18AlImran121148.mp3|019-AlImran149161.mp3|020-AlImran162200.mp3|021-SuraNisa122.mp3|022a-SuraNisa2333.mp3|022b-An-nisa34-35.mp3|023-suraNisa36-76.mp3|024-SuraNisa77104.mp3|025-SuraNisa105143.mp3|026-SuraNisa144-176.mp3|027-SuraMaida1-32.mp3|028-SuraMaida32-63.mp3|029-AlMaida6493.mp3|029b-Al-maida94-100.mp3online-audio-converter.com.mp3|030-AlMaida101120.mp3|031-Al-anam132.mp3|031-Al-anam33-70.mp3|032-Al-anam71-111.mp3|033-Al-anam112-165.mp3|034-Al-araf1-25.mp3|035-al-araf26-58.mp3|036-Al-araf59-102.mp3|037-Al-araf103-128.mp3|038-Al-aaraf129-162.mp3|039-Al-aaraf163-181.mp3|040-AlAraaf182AlInfal19.mp3|041-AlInfal20-44.mp3|042-AlInfal4575.mp3|043-A-tauba1-24.mp3|044-At-tauba25-59.mp3|045-AtTauba6099.mp3|046-AtTauba100129.mp3|047-AlYunus0140.mp3|048-SuraYounas41-67.mp3|049-SurahYunus68-109.mp3|050-SurahHud01-48.mp3|051-SurahHud49-95.mp3|052-SurahHud96-123.mp3|053-SurahYusuf1-18.mp3|054-SurahYusuf19-29.mp3|055-SurahYusuf30-50.mp3|056-SurahYusuf51-87.mp3|057-SurahYusuf88-111.mp3|058-SurahRaad1-34.mp3|059-SurahRad35ToSurahIbrahim23.mp3|060-SurahIbrahim24-51.mp3|061-SurahHijr1To40.mp3|062-Al-hijr41ToAn-nahl21.mp3|063-An-nahl22-50.mp3|064-SurahAn-nahl51-78.mp3|065-SurahAn-nahl77-128.mp3|066-BaniIsrael1-30.mp3|How-to-make-best-use-of-this-course.mp3|Huqooq1_0001.mp3|QuranKeHuqooqPart2.mp3"},
{n="Tafseer Urdu - Dr. Mir Aneesuddin (Mukammal 219 Dars)", l="Urdu", i="tafsirurdudr.miraneesuddinlate", s="bk_urdu_anees", d="000-Quran-Intro.mp3|001-Al-Fatihah.mp3|002-Al-Baqara-1-16.mp3|002-Al-Baqara-101-117.mp3|002-Al-Baqara-118-141.mp3|002-Al-Baqara-164-177.mp3|002-Al-Baqara-17-39.mp3|002-Al-Baqara-178-196.mp3|002-Al-Baqara-197-217.mp3|002-Al-Baqara-258-273 (1).mp3|002-Al-Baqara-258-273.mp3|002-Al-Baqara-274-286.mp3|002-Al-Baqara-40-73.mp3|002-Al-Baqara-74-100.mp3|003-Al-Imran-1-20.mp3|003-Al-Imran-116-148.mp3|003-Al-Imran-149-175.mp3|003-Al-Imran-176-200.mp3|003-Al-Imran-21-51.mp3|003-Al-Imran-52-82.mp3|003-Al-Imran-83-115.mp3|004-An-Nisa-1-21.mp3|004-An-Nisa-117-147.mp3|004-An-Nisa-148-177 (1).mp3|004-An-Nisa-148-177.mp3|004-An-Nisa-22-43.mp3|004-An-Nisa-71-93.mp3|004-An-Nisa-94-116.mp3|005-Al-Maida-1-16.mp3|005-Al-Maida-17-43.mp3|005-Al-Maida-44-66 (1).mp3|005-Al-Maida-44-66.mp3|005-Al-Maida-67-93.mp3|005-Al-Maida-94-120.mp3|006-Al-Anam-1-41.mp3|006-Al-Anam-122-144.mp3|006-Al-Anam-145-166.mp3|006-Al-Anam-42-70.mp3|006-Al-Anam-71-95.mp3|006-Al-Anam-96-121.mp3|007-Al-Araf-1-25.mp3|007-Al-Araf-171-206.mp3|007-Al-Araf-26-43.mp3|007-Al-Araf-44-58.mp3|007-Al-Araf-59-170.mp3|008-Al-Anfal-1-28.mp3|008-Al-Anfal-29-51.mp3|008-Al-Anfal-52-75.mp3|009-At-Taubah-1-24.mp3|009-At-Taubah-111-129.mp3|009-At-Taubah-43-72.mp3|009-At-Taubah-73-93.mp3|009-At-Taubah-94-110.mp3|010-Yunus-1-10.mp3|010-Yunus-11-30.mp3|010-Yunus-31-60.mp3|010-Yunus-61-92.mp3|010-Yunus-93-109.mp3|011-Hud-1-8.mp3|011-Hud-36-68.mp3|011-Hud-69-95.mp3|011-Hud-9-35.mp3|011-Hud-96-123.mp3|012-Yousuf-1-111.mp3|013-Ar-Ra_ad-1-11.mp3|013-Ar-Ra_ad-12-27.mp3|013-Ar-Ra_ad-28-43.mp3|014-Ibrahim-22-52.mp3|015-Al-Hijr-1-50.mp3|015-Al-Hijr-51-99.mp3|016-An-Nahal-1-25.mp3|016-An-Nahal-111-128.mp3|016-An-Nahal-26-60.mp3|016-An-Nahal-61-83.mp3|016-An-Nahal-84-110.mp3|017-Bani-Israel-1-10.mp3|017-Bani-Israel-11-22.mp3|017-Bani-Israel-33-44 (1).mp3|017-Bani-Israel-33-44.mp3|017-Bani-Israel-45-70.mp3|017-Bani-Israel-71-111.mp3|018-Al-Kahaf-1-26.mp3|018-Al-Kahaf-27-53.mp3|018-Al-Kahaf-54-82.mp3|018-Al-Kahaf-84-110.mp3|019-Maryam-1-40.mp3|019-Maryam-41-75.mp3|019-Maryam-76-98.mp3|020-Taha-1-104.mp3|020-Taha-105-135.mp3|021-Al-Anbiya-1-33.mp3|021-Al-Anbiya-34-77.mp3|021-Al-Anbiya-78-112.mp3|022-Al-Hajj-1-25.mp3|022-Al-Hajj-26-51.mp3|022-Al-Hajj-52-78.mp3|023-Al-Muminun-1-50.mp3|023-Al-Muminun-51-118.mp3|024-An-Nur-1-26.mp3|024-An-Nur-27-45.mp3|024-An-Nur-46-64.mp3|025-Al-Furqan-1-34.mp3|025-Al-Furqan-35-77.mp3|026-Ash-Shu_ra-1-89.mp3|026-Ash-Shu_ra-160-227.mp3|026-Ash-Shu_ra-90-159.mp3|027-An-Namal-1-59.mp3|027-An-Namal-60-93.mp3|028-Al-Qasas-1-41.mp3|028-Al-Qasas-42-67.mp3|028-Al-Qasas-68-88.mp3|029-Al-Ankabut-1-35.mp3|029-Al-Ankabut-36-69.mp3|030-Ar-Rum-1-32 (1).mp3|030-Ar-Rum-1-32.mp3|031-Luqman-1-34.mp3|032-As-Sajda-1-30.mp3|033-Al-Ahzab-1-27 (1).mp3|033-Al-Ahzab-1-27.mp3|033-Al-Ahzab-28-47.mp3|033-Al-Ahzab-53-73.mp3|034-Saba-1-30.mp3|034-Saba-31-54.mp3|035-Faatir-1-7.mp3|035-Faatir-38-45.mp3|035-Faatir-8-37.mp3|036-Yaasiin-1-40.mp3|036-Yaasiin-41-83.mp3|037-As-Saffaat-1-82.mp3|038-Saad-1-64.mp3|038-Saad-65-88.mp3|039-Az-Zumar-1-9.mp3|039-Az-Zumar-10-41.mp3|039-Az-Zumar-42-75.mp3|040-Ghaafir-1-50.mp3|040-Ghaafir-51-85.mp3|041-Fussilaat-1-25.mp3|041-Fussilaat-26-54.mp3|044-Ad-Dukhan-1-29.mp3|044-Ad-Dukhan-30-59.mp3|045-Al-Jathiya-1-21.mp3|045-Al-Jathiya-22-37.mp3|046-Al-Ahqaf-1-14.mp3|046-Al-Ahqaf-15-35.mp3|048-Al-Fath-1-29.mp3|049-Al-Hujraat-1-18.mp3|050-Qaaf-1-15.mp3|050-Qaaf-16-45.mp3|051-Az-Zariyat-1-46.mp3|051-Az-Zariyat-47-60.mp3|052-At-Tur-1-49.mp3|053-An-Najm-1-62.mp3|054-Al-Qamar-1-40.mp3|054-Al-Qamar-41-55.mp3|056-Al-Waqiyah-1-96.mp3|057-Al-Hadeed-23-29 (1).mp3|057-Al-Hadeed-23-29.mp3|057-Al-Hadeed-7-22.mp3|058-Al-Mujadila-1-22.mp3|059-Al-Hashar-1-24.mp3|060-Al-Mumtahina-1-13.mp3|061-As-Saff-1-10.mp3|062-Al-Jumuah-1-14.mp3|063-Al-Munafiqun-1-11.mp3|064-At-Taghabun-1-18.mp3|065-At-Talaq-1-7.mp3|065-At-Talaq-8-12.mp3|066-At-Tahrim-1-12.mp3|067-Al-Mulk-1-14.mp3|067-Al-Mulk-15-30.mp3|068-Al-Qalam-1-33.mp3|068-Al-Qalam-34-52.mp3|069-Al-Haaqqa-1-12.mp3|069-Al-Haaqqa-13-52.mp3|070-Al-Ma_arij-1-44.mp3|071-Nuh-1-28.mp3|072-Al-Jinn-1-28.mp3|073-Al-Muzammil-1-20.mp3|074-Al-Mudassir-1-56.mp3|075-Al-Qayamah-1-40.mp3|076-Al-Dahar-1-31.mp3|077-Al-Mursilaat-1-50.mp3|078-Al-Naba-1-40.mp3|079-Al-Naziyat-1-46.mp3|080-Abasa-1-42.mp3|081-Al-Takwir-1-29.mp3|082-Al-Infitar-1-19.mp3|083-Al-Mutaffifeen-1-36.mp3|084-Al-Inshiqaaq-1-25.mp3|085-Al-Buruj-1-22.mp3|086- Al Tariq 87.mp3|087-Al Aala 67.mp3|088-Al-Ghashiya.mp3|089-Al-Fajar.mp3|090- Al-Balad.mp3|091-Al-Shams-1-15.mp3|092-Al-Lail-1-21.mp3|093-Al-Duha-1-11.mp3|094-Alam-Nashrah-1-8.mp3|095-Al-Teen-1-8.mp3|096-Al-Alaq-1-19.mp3|097-Al-Qadar-1-5.mp3|098-Al-Bayyina-1-8.mp3|099-Al-Zilzaal-1-8.mp3|100-Al-Adiyaat-1-11.mp3|101-Al-Qariyah-1-11.mp3|102-Al-Takathur-1-8.mp3|103-Al-Asr-1-3.mp3|104-Al-Humaza-1-9.mp3|105-Al-Feel-1-5.mp3|106-Quraish-1-4.mp3|107-Al-Maun-1-7.mp3|108-Al-Kauthar-1-3.mp3|109-Al-Kafiroon-1-6.mp3|110-An-Nasr-1-3.mp3|111-Al-Lahab-1-5.mp3|112-Al-Iklhas-1-4.mp3|113-Al-Falaq-1-5.mp3|114-An-Nas-1-6.mp3"},
{n="Fahm-ul-Quran Urdu Tafseer - Dr. Farhat Hashmi (108 Dars)", l="Urdu", i="TAFSIRURDUDR.FARHATHASHMI", s="bk_urdu_fahm", d="FQ2012-01A-Al-Fatihah_-_Al-Baqarah_1-29.mp3|FQ2012-01B-Al-Baqarah_30-86.mp3|FQ2012-01C-Al-Baqarah_87-141.mp3|FQ2012-02A-Al-Baqarah_142-186.mp3|FQ2012-02B-Al-Baqarah_187-221.mp3|FQ2012-02C-Al-Baqarah_222-252.mp3|FQ2012-03A-Al-Baqarah_253-274.mp3|FQ2012-03B-Al-Baqarah_275-286_-_Aal-e-Imran_1-30.mp3|FQ2012-03C-Aal-e-Imran_31-91.mp3|FQ2012-04A-Aal-e-Imran_92-120.mp3|FQ2012-04B-Aal-e-Imran_121-155.mp3|FQ2012-04C-Aal-e-Imran_156-200.mp3|FQ2012-04D-Al-Nisa_1-23.mp3|FQ2012-05A-Al-Nisa_24-35.mp3|FQ2012-05B-Al-Nisa_36-87.mp3|FQ2012-05C-Al-Nisa_88-147.mp3|FQ2012-06A-Al-Nisa_148-176.mp3|FQ2012-06B-Al-Maidah_1-26.mp3|FQ2012-06C-Al-Maidah_27-82.mp3|FQ2012-07A-Al-Maidah_83-100.mp3|FQ2012-07B-Al-Maidah_101-120_-_Al-Anam_1-19.mp3|FQ2012-07C-Al-Anam_20-55.mp3|FQ2012-07D-Al-Anam_56-110.mp3|FQ2012-08A-Al-Anam_111-140.mp3|FQ2012-08B-Al-Anam_141-165.mp3|FQ2012-08C-Al-Araf_1-39.mp3|FQ2012-08D-Al-Araf_40-87.mp3|FQ2012-09A-Al-Araf_88-141.mp3|FQ2012-09B-Al-Araf_142-188.mp3|FQ2012-09C-Al-Araf_189-206_-_Al-Anfal_1-40.mp3|FQ2012-10A-Al-Anfal_41-75.mp3|FQ2012-10B-Al-Tawbah_1-59.mp3|FQ2012-10C-Al-Tawbah_60-93.mp3|FQ2012-11A-Al-Tawbah_94-114.mp3|FQ2012-11B-Al-Tawbah_115-129_-_Yunus_1-20.mp3|FQ2012-11C-Al-Tawbah_21-73.mp3|FQ2012-11D-Yunus_74-109_-_Hud_1-5.mp3|FQ2012-12A-Hud_6-68.mp3|FQ2012-12B-Hud_69-123_-_Yusuf_1-7.mp3|FQ2012-12C-Yusuf_8-52.mp3|FQ2012-13A-Yusuf_53-87.mp3|FQ2012-13B-Yusuf_88-111_-_Al-Rad_1-7.mp3|FQ2012-13C-Al-Rad_8-43.mp3|FQ2012-13D-Ibrahim_1-52.mp3|FQ2012-14A-Al-Hijr_1-79.mp3|FQ2012-14B-Al-Hijr_80-99_-_Al-Nahl_1-34.mp3|FQ2012-14C-Al-Nahl_35-83.mp3|FQ2012-14D-Al-Nahl_84-128.mp3|FQ2012-15A-Bani_Israil_1-39.mp3|FQ2012-15B-Bani_Israil_40-111_-_Al-Kahf_1-8.mp3|FQ2012-15C-Al-Kahf_9-74.mp3|FQ2012-16A-Al-Kahf_75-110_-_Maryam_1-40.mp3|FQ2012-16B-Maryam_41-98.mp3|FQ2012-16C-Ta-Ha_1-76.mp3|FQ2012-16D-Ta-Ha_77-135.mp3|FQ2012-17A-Al-Anbiya_1-50.mp3|FQ2012-17B-Al-Anbiya_51-112_-_Al-Hajj_1-22.mp3|FQ2012-17C-Al-Hajj_23-78.mp3|FQ2012-18A-Al-Muminun_1-61.mp3|FQ2012-18B-Al-Muminun_62-118.mp3|FQ2012-18C-Al-Nur_1-31.mp3|FQ2012-18D-Al-Nur_32-64_-_Al-Furqan_1-20.mp3|FQ2012-19A-Al-Furqan_21-77.mp3|FQ2012-19B-Al-Shuara_1-227.mp3|FQ2012-19C-Al-Naml_1-59.mp3|FQ2012-20A-Al-Naml_60-93_-_Al-Qasas_1-22.mp3|FQ2012-20B-Al-Qasas_23-88.mp3|FQ2012-20C-Al-Ankabut_1-44.mp3|FQ2012-21A-Al-Ankabut_45-69_-_Al-Rum_1-27.mp3|FQ2012-21B-Al-Rum_28-60_-_Luqman_1-34.mp3|FQ2012-21C-Al-Sajdah_1-30_-_Al-Ahzab_1-30.mp3|FQ2012-22A-Al-Ahzab_31-55.mp3|FQ2012-22B-Al-Ahzab_56-73_-_Saba_1-14.mp3|FQ2012-22C-Saba_15-54_-_Fatir_1-26.mp3|FQ2012-22D-Fatir_27-45_-_Ya-Sin_1-21.mp3|FQ2012-23A-Ya-Sin_22-83.mp3|FQ2012-23B-Al-Saffat_1-182.mp3|FQ2012-23C-Saad_1-88.mp3|FQ2012-23D-Al-Zumar_1-31.mp3|FQ2012-24A-Al-Zumar_32-75.mp3|FQ2012-24B-Al-Mumin_1-59.mp3|FQ2012-24C-Al-Mumin_60-85_-_Ha-Mim_Al-Sajdah_1-18.mp3|FQ2012-24D-Ha-Mim_Al-Sajdah_19-46.mp3|FQ2012-25A-Ha-Mim_Al-Sajdah_47-54_-_Al-Shura_1-29.mp3|FQ2012-25B-Al-Shura_30-53_-_Al-Zukhraf_1-73.mp3|FQ2012-25B-Al-Shura_30-53_-_Al-Zukhruf_1-73.mp3|FQ2012-25C-Al-Zukhraf_74-89_-_Al-Jathiah.mp3|FQ2012-25C-Al-Zukhruf_74-89_-_Al-Jathiah.mp3|FQ2012-26A-Al-Ahqaf.mp3|FQ2012-26B-Muhammad_-_Al-Fath_1-17.mp3|FQ2012-26C-Al-Fath_18-29_-_Al-Hujuraat.mp3|FQ2012-26D-Qaaf_-_Al-Zariyaat_1-30.mp3|FQ2012-27A-Al-Zariyaat_31-60_-_Al-Toor.mp3|FQ2012-27B-Al-Najm_-_Al-Qamar.mp3|FQ2012-27C-Al-Rahman_-_Al-Waqiah.mp3|FQ2012-27D-Al-Hadid.mp3|FQ2012-28A-Al-Mujadalah.mp3|FQ2012-28B-Al-Hashr_-_Al-Mumtahinah.mp3|FQ2012-28C-Al-Saff_-_Al-Munafiqun.mp3|FQ2012-28D-Al-Taghabun_-_Al-Tahrim.mp3|FQ2012-29A-Al-Mulk_-_Al-Qalam.mp3|FQ2012-29B-Al-Haqqah_-_Al-Jinn.mp3|FQ2012-29C-Al-Muzzammil_-_Al-Mursalaat.mp3|FQ2012-30A-Al-Naba_-_Al-Infitar.mp3|FQ2012-30B-Al-Mutaffifin_-_Al-Shams.mp3|FQ2012-30C-Al-Lail_-_Al-Asr.mp3|FQ2012-30D-Al-Humazah_-_Al-Naas.mp3|FQ2012-30E-Duaa.mp3"},
{n="Seerat un Nabi - Dr. Israr Ahmed (5 Bayanat)", l="Urdu", i="seeratunnabi_bydrisrarahmad_audio", s="bk_urdu_israr5", d="Seerat_lec_1_dr_israr.mp3|Seerat_lec_2_dr_israr.mp3|Seerat_lec_3_dr_israr.mp3|Seerat_lec_4_dr_israr.mp3|Seerat_lec_5_dr_israr.mp3"},
{n="Seerat Khalid Ibn Al Waleed (RA) - Darussalam Urdu (2 Hisse)", l="Urdu", i="InUrduDarusSalamPresentsSeeratKhalidIbnAlWaleedRA", s="bk_urdu_khalid", d="In Urdu DarusSalam Presents Seerat Khalid Ibn al Waleed {R A}.mp3|Jahannum Ka Akhri Banda By Maulana Manzoor Yousuf Sahab.mp3"},
{n="Urdu Islamic Bayan Collection - Best Reminder (79 Bayanat)", l="Urdu", i="UrduAudioIslamicBayanCollectionBestForEver", s="bk_urdu_bestbayan79", c="bayan", d="(01)  Best Reminder Fikre Aakhirat-Abu Zaid Zameer Repack.mp3|(01) Best Reminder-JAHANNAM KA BYAN.mp3|(3) Aakhri Jannati ┇ آخری جنتی ┇ #Jannat #Jannati ┇Amazing Clip.mp3|(4) Qabar ka Manzar ┇ قبر کا منظر ┇ Amazing Clip.mp3|297  REHMANI AULIYA  SHAITANI AULIYA  . B .  { SHAIKH SYED MERAJ RABBANI }.mp3|786 Kya Hai_Abu Zaid Zameer.mp3|(A)  Haqeeqat - e - Jin Aur Uska Elaj   . A .  { SHAIKH SYED MERAJ RABBANI }.mp3|(B)  Haqeeqat - e - Jin Aur Uska Elaj   . B . { SHAIKH SYED MERAJ RABBANI }.mp3|(C)  Haqeeqat - e - Jin Aur Uska Elaj   . C . { SHAIKH SYED MERAJ RABBANI }.mp3|(D)  Haqeeqat - e - Jin Aur Uska Elaj   . D .  { SHAIKH SYED MERAJ RABBANI }.mp3|(E)  Haqeeqat - e - Jin Aur Uska Elaj   . E .  { SHAIKH SYED MERAJ RABBANI }.mp3|(F)  Haqeeqat - e - Jin Aur Uska Elaj   . F .  { SHAIKH SYED MERAJ RABBANI }.mp3|(G)  Haqeeqat - e - Jin Aur Uska Elaj   . G .  { SHAIKH SYED MERAJ RABBANI }.mp3|(H)  Haqeeqat - e - Jin Aur Uska Elaj   . H .  { SHAIKH SYED MERAJ RABBANI }.mp3|(I)  Haqeeqat - e - Jin Aur Uska Elaj   . I .  { SHAIKH SYED MERAJ RABBANI }.mp3|(J)  Haqeeqat - e - Jin Aur Uska Elaj   . J .  { SHAIKH SYED MERAJ RABBANI }.mp3|(K)  Haqeeqat - e - Jin Aur Uska Elaj   . K .  { SHAIKH SYED MERAJ RABBANI }.mp3|(L)  Haqeeqat - e - Jin Aur Uska Elaj   . L .  { SHAIKH SYED MERAJ RABBANI }.mp3|ALLAH KE NAZDEEK CHAAR SABSE NEIK AURTEIN-Sis~Amtul~Matin.mp3|Aapne ISLAM Kab Qabul Kiya-Kya Aapko Parde Me Garmi Nahi Lagti.mp3|Aazmais~Sabr-Urdu Islamic Downloads.mp3|Ahle Hadees Ke Mutalliq Shubhat Ka Izaala_AbuZaidZameer.mp3|Allah Par Tawakkal   -#-  SHAIKH  TAUSEEFUR  REHMAN.mp3|Allah hi per bharosa ┇ اللہ ہی پر بھروسہ  ┇ Amazing Clip.mp3|Allah is ar-Rab - The Sustainer - Amazing Clip.mp3|Allah ke Padosi ┇ اللہ کے پڑوسی ┇ Amazing Video ┇ Amazing CLip.mp3|Allah ke deen me azmaishen ┇ Amazing Clip.mp3|Allah koun Hai By Shk Tauseef Ur Rehman (Dubai).mp3|Amazing misaal Silah Rehmi ki┇ صلح رحمی کی دلچسپ مثال ┇ Amazing Clip.mp3|Azaab e Qabr - Shub'haat aur Jawabaat - Abu Zaid Zameer.mp3|Azmais~Istiqamat-jajees ansari-Urdu Islamic Downloads.mp3|BAJRANG DAL-Hindu Neta Kaise Islam Qabul Kiya-Amazing Clip.mp3|Be-Sharam Aurat Koun ؟ By Dr  Farhat Hashmi.mp3|Beemari se Maut tak~by  Abu Zaid Zameer.mp3|CHAR IMAM . A .  { SHAIKH SYED MERAJ RABBANI }.mp3|CHAR IMAM . B .  { SHAIKH SYED MERAJ RABBANI }.mp3|Dikhawa-Karna-Amazing Clip.mp3|Dua ka asar ┇ دعا کا اثر ┇Amazing Video~ LearnQuran.net.mp3|Duniya Ki Haqiqat By Sheikh Syed Tauseef ur Rehman Rashidi 03-March-2015.mp3|Duniya Ki Haqiqat-(Amazing Clip) Abu Zaid Zameer.mp3|Duniya ki Museebaten-Abu Zaid Zameer.mp3|FAHASHI SE BACHO-Full Clip.mp3|Fahashi Se Bacho~Amazing Clip.mp3|Fikr E Akhirat By Shaikh Sana Ullah Madani.mp3|Fikr e Aakhirat - Shaikh Abu Zaid Zameer.mp3|Fikr-e-Aakhirat Aur Uske Taqaazey By Shaikh Tauseef ur Rahman.mp3|Galat Aqaaid-O-Nazariyaat Shaikh Maulana Jarjees Ansari Molana Jarjis Siraji 2015.mp3|Ghair Islami Rasam O Riwaj By Shaikh Tauseef Ur Rahman- UK 2015.mp3|Gham_Na_Karein___by_Shaikh_Sanaullah_Madni.mp3|Gharon Ki Islah By Adv. Faiz Syed.mp3|Gunaho ke Nuqsanat_Shaikh Sanaullah Madani.mp3|HAJJ  KA AAMI PAIGAAM . A .    { SHAIKH SYED MERAJ RABBANI }.mp3|HAJJ  KA AAMI PAIGAAM . B .    { SHAIKH SYED MERAJ RABBANI }.mp3|Haq Pe Kaun.mp3|Har Nafs Ko Maut Ka Maja Chakhna Hai- (Amazing Clip) SK Sanaullah Madni.mp3|Hindu Dharm Aur Mazhabe Islam Mein Yaksaniyat - Dr. Zakir Naik.mp3|Hindu ladka Islam qabul karte huye.mp3|ISLAM  AUR  FIRKA  PARASTI  . A . { SHAIKH SYED MERAJ RABBANI }.mp3|ISLAM  AUR  FIRKA  PARASTI  . B . { SHAIKH SYED MERAJ RABBANI }.mp3|ISLAM ME AISE Q HAI.mp3|ISLAM MEIN AURTOUN KA MUQHAAM~By~Sis~Amtul~Mateen.mp3|Imaan Aur Aazmaish By Adv. Faiz syed.mp3|Insan Allah Subhanawatala Ki  Behtareen Maqlooq-by Sister-(Science).mp3|Islam Aur DehsatGardi (Terrorism) - Maulana Jarjis Ansari, Siraji - 2016 - इस्लाम और दहशत गर्दी - Urdu Islamic Downloads.mp3|Islam Mein Aurton Ka Maqam~SK Meraj Rabbani.mp3|Islam Rahmat Hai~SK Jarjees Ansari in Mau.mp3|Islam insaniyat ke liye ramat na ke zahmat  by DR Zakir Naik.mp3|JANNAT.mp3|Jadu   -#-  SHAIKH  TAUSEEFUR  REHMAN  -#-.mp3|JahanNum Say kaisay Bachay By Shk Tauseef Ur Rehman.mp3|Jahannam ka Aza'ab, By Sheikh Faizullah Madani.mp3|Jahez Ki Lanat - दहेज की लानत - Dowry a curse By Molana Jarjees Ansari - Siraji .mp3|Jannat Kaisi Hai-1-4.mp3|Jannat Kaisi Hai-2-2.mp3|Jannat Kaisi Hai-3-4.mp3|Jannat Kaisi Hai-4-4.mp3|Jannat Me Le Jane Wale Aamal Maulana Jarjees Ansari Domanpura Hibba Mau.mp3|Jannat ka Shauq aur Jahannam se Khauf - Abu Zaid Zameer.mp3|Jarjees Ansari  Murawwaja Batil Aqaid Ka Postmartam By Shaikh Jarjees Ansari Hafizahullah - UID.mp3"},
{n="Tafseer-e-Quran Qasmi - Mukammal Dora (573 Dars)", l="Urdu", i="TafseereQuranUrdu", s="bk_urdu_qasmi573", c="bayan", d="0010_surah al-fatiha.mp3|0020_p1R1SurahBaqarahA1-7.mp3|0030_p1R2SurahBaqarahA8-20.mp3|0040_p1R3SurahBaqarahA21-29.mp3|0050_p1R4SurahBaqarahA30-39.mp3|0060_p1R5SurahBaqarahA40-46.mp3|0070_p1R6SurahBaqarahA47-59.mp3|0080_p1R7SurahBaqarahA60-61.mp3|0090_p1R8SurahBaqarahA62-71.mp3|0100_p1R9SurahBaqarahA72-82.mp3|0110_p1R10SurahBaqarahA83-86.mp3|0120_p1R11SurahBaqarahA87-96.mp3|0130_p1R12SurahBaqarahA97-103.mp3|0140_p1R13SurahBaqarahA104-112.mp3|0150_p1R14SurahBaqarahA113-121.mp3|0160_p1R15SurahBaqarahA122-129.mp3|0170_p1R16SurahBaqarahA130-141.mp3|0180_p2R1AlBaqaraA142-147.mp3|0190_p2R2AlBaqaraA148-152.mp3|0200_p2R3AlBaqaraA153-163.mp3|0210_p2R4AlBaqaraA164-167.mp3|0220_p2R5AlBaqaraA168-176.mp3|0230_p2R6AlBaqaraA177-182.mp3|0240_p2R7AlBaqaraA183-188.mp3|0250_p2R8AlBaqaraA189-196.mp3|0260_p2R9AlBaqaraA197-210.mp3|0270_p2R10AlBaqaraA211-216.mp3|0280_p2R11AlBaqaraA217-221.mp3|0290_p2R12AlBaqaraa222-228.mp3|0300_p2R13AlBaqaraA229-231.mp3|0310_p2R14AlBaqaraA232-235.mp3|0320_p2R15AlBaqaraA236-242.mp3|0330_p2R16AlBaqaraA243-248.mp3|0340_p2R17AlBaqaraA248-252.mp3|0350_p3R1AlBaqaraA253.mp3|0360_p3R2AlBaqaraR34A254-257.mp3|0370_p3R3AlBaqaraR35A258-260.mp3|0380_p3R4AlBaqaraR36A261-266.mp3|0390_p3R5AlBaqaraA267-273.mp3|0400_p3R6AlBaqaraA274-281.mp3|0410_p3R7AlBaqaraA282-283.mp3|0415_p3R8AlBaqaraA284-286.mp3|0420_p3R9SurahAaleimranA1-9.mp3|0430_p3R10SurahAaleimranA10-20.mp3|0440_p3R11SurahAaleimranA21-30.mp3|0450_p3R12SurahAaleimranA31-41.mp3|0460_p3R13SurahAaleimranA42-54.mp3|0470_p3R14SurahAaleimranA55-63.mp3|0480_p3R15SurahAaleimranA64-71.mp3|0490_p3R16SurahAaleimranA72-80.mp3|0500_p3R17SurahAaleimranA81-91.mp3|0505_p4R1SurahAaleimranA92-101.mp3|0506_p4R2SurahAaleimranA102-109.mp3|0510_p4R3SurahAaleimranA110-120.mp3|0520_p4R4SurahAaleimranA121-129.mp3|0530_p4R5SurahAaleimranA130-143.mp3|0540_p4R6SurahAaleimranA144-148.mp3|0550_p4R7SurahAaleimranA149-155.mp3|0560_p4R8SurahAaleimranA156-171.mp3|0570_p4R9SurahAaleimranA172-180.mp3|0580_p4R10SurahAaleimranA181-189.mp3|0590_p4R11SurahAaleimranA190-200.mp3|0600_p4R12SurahNisaaA1-10.mp3|0610_p4R13SurahNisaaA11-14.mp3|0620_p4R14SurahNisaaA15-22.mp3|0630_p4SurahNisaaA23.mp3|0660_p5R1SurahNisaaA24-25.mp3|0670_p5R2SurahNisaaA26-33.mp3|0680_p5R3SurahNisaaA34-42.mp3|0690_p5R4SurahNisaaA43-50.mp3|0700_p5R5SurahNisaaA51-59.mp3|0710_p5R6SurahNisaaA60-70.mp3|0720_p5R7SurahNisaaA71-76.mp3|0730_p5R8SurahNisaaA77-87.mp3|0740_p5R9SurahNisaaA88-91.mp3|0750_p5R10SurahNisaaA92-96.mp3|0760_p5R11SurahNisaaA97-100.mp3|0770_p5R12SurahNisaaA101-104.mp3|0780_p5R13SurahNisaaA105-112.mp3|0790_p5R14SurahNisaaA113-115.mp3|0800_p5R15SurahNisaaA116-126.mp3|0810_p5R16SurahNisaaA127-134.mp3|0820_p5R17SurahNisaaA135-141.mp3|0830_p5SurahNisaaA142-147.mp3|0840_p6R1SurahNisaaA148-152.mp3|0850_p6R2SurahNisaaA153-162.mp3|0860_p6R3SurahNisaaA163-171.mp3|0870_p6R4SurahNisaaA172-176.mp3|0880_p6R5SurahMaaidaA1-5.mp3|0890_p6R6SurahMaaidaA6-11.mp3|0900_p6R7SurahMaaidaA12-19.mp3|0910_p6R8SurahMaaidaA20-26.mp3|0920_p6R9SurahMaaidaA27-34.mp3|0930_p6R10SurahMaaidaA35-43.mp3|0940_p6R11SurahMaaidaA44-50.mp3|0950_p6R12SurahMaaidaA51-56.mp3|0960_p6R13SurahMaaidaA57-66.mp3|0970_p6R14SurahMaaidaA67-77.mp3|0980_p6SurahMaaidaA78-82.mp3|0981_p7R1SurahMaaidaA83-86.mp3|0982_p7R2SurahMaaidaA87-93.mp3|0983_p7R3SurahMaaidaA94-100.mp3|0984_p7R4SurahMaaidaA101-108.mp3|0990_p7R5SurahMaaidaA109-115.mp3|1000_p7R6SurahMaaidaA116-120.mp3|1010_p7R7SurahAnaamA1-10.mp3|1020_p7R8SurahAnaamA11-20.mp3|1030_p7R9SurahAnaamA21-30.mp3|1040_p7R10SurahAnaamA31-41.mp3|1050_p7R11SurahAnaamA42-50.mp3|1060_p7R12SurahAnaamA51-55.mp3|1070_p7R13SurahAnaamA56-60.mp3|1080_p7R14SurahAnaamA61-70.mp3|1090_p7R15SurahAnaamA71-82.mp3|1100_p7R16SurahAnaamA83-90.mp3|1110_p7R17SurahAnaamA91-94.mp3|1120_p7R18SurahAnaamA95-100.mp3|1130_p7R19SurahAnaamA101-110.mp3|1180_p8R1SurahAnaamA111-121.mp3|1190_p8R2SurahAnaamA122-129.mp3|1200_p8R3SurahAnaamA130-140.mp3|1210_p8R4SurahAnaamA141-144.mp3|1220_p8R5SurahAnaamA145-150.mp3|1230_p8R6SurahAnaamA151-154.mp3|1240_p8R7SurahAnaamA155-165.mp3|1250_p8R8SurahAaraafA1-10.mp3|1260_p8R9SurahAaraafA11-25.mp3|1270_p8R10SurahAaraafA26-31.mp3|1280_p8R11SurahAaraafA32-39.mp3|1290_p8R12SurahAaraafA40-47.mp3|1300_p8R13SurahAaraafA48-53.mp3|1310_p8R14SurahAaraafA54-58.mp3|1320_p8R15SurahAaraafA59-64.mp3|1330_p8R16SurahAaraafA65-72.mp3|1340_p8R17SurahAaraafA73-84.mp3|1350_p8SurahAaraafA85-87.mp3|1360_p9R1SurahAaraafA88-93.mp3|1370_p9R2SurahAaraafA94-99.mp3|1380_p9R3SurahAaraafA100-108.mp3|1390_p9R4SurahAaraafA109-126.mp3|1400_p9R5SurahAaraafA127-129.mp3|1410_p9R6SurahAaraafA130-141.mp3|1420_p9R7SurahAaraafA142-147.mp3|1430_p9R8SurahAaraafA148-151.mp3|1440_p9R9SurahAaraafA152-157.mp3|1450_p9R10SurahAaraafA158-162.mp3|1460_p9R11SurahAaraafA163-171.mp3|1470_p9R12SurahAaraafA172-181.mp3|1480_p9R13SurahAaraafA182-188.mp3|1490_p9R14SurahAaraafA189-206.mp3|1500_p9R15SurahAnfalA1-10.mp3|1510_p9R16SurahAnfalA11-19.mp3|1520_p9R17SurahAnfalA20-28.mp3|1530_p9R18SurahAnfalA29-37.mp3|1540_p9R19SurahAnfalA38-40.mp3|1545_p10R1SurahAnfaalA41-44.mp3|1546_p10R2SurahAnfaalA45-48.mp3|1547_p10R3SurahAnfaalA49-58.mp3|1548_p10R4SurahAnfaalA59-64.mp3|1549_p10R5SurahAnfaalA65-69.mp3|1550_p10R6SurahAnfaalA70-75.mp3|1560_p10R7SurahTaubahA1-6.mp3|1570_p10R8SurahTaubahA7-16.mp3|1580_p10R9SurahTaubahA17-24.mp3|1590_p10R10SurahTaubahA25-29.mp3|1600_p10R11SurahTaubahA30-37.mp3|1610_p10R12SurahTaubahA38-42.mp3|1620_p10R13SurahTaubahA43-59.mp3|1630_p10R14SurahTaubahA60-66.mp3|1640_p10R15SurahTaubahA67-72.mp3|1650_p10R16SurahTaubahA73-80.mp3|1660_p10R17SurahTaubahA81-89.mp3|1670_p10R18SurahTaubahA90-93.mp3|1730_p11R1SurahTaubahA94-99.mp3|1740_p11R2SurahTaubahA100-110.mp3|1750_p11R3SurahTaubahA111-118.mp3|1760_p11R4SurahTaubahA119-122.mp3|1770_p11R5SurahTaubaA123-129.mp3|1780_p11R6SurahYunusA1-10.mp3|1790_p11R7SurahYunusA11-20.mp3|1800_p11R8SurahYunusA21-30.mp3|1810_p11R9SurahYunusA31-40.mp3|1820_p11R10SurahYunusA41-53.mp3|1830_p11R11SurahYunusA54-60.mp3|1840_p11R12SurahYunusA61-70.mp3|1850_p11R13SurahYunusA71-82.mp3|1860_p11R14SurahYunusA83-92.mp3|1870_p11R15SurahYunusA93-103.mp3|1880_p11R16SurahYunusA104-109.mp3|1890_p11R17SurahHuud1-5.mp3|1930_p12R1SurahHuudA6-8.mp3|1940_p12R2SurahHuudA9-24.mp3|1950_p12R3SurahHuudA25-35.mp3|1960_p12R4SurahHuudA36-49.mp3|1970_p12R5SurahHuudA50-60.mp3|1980_p12R6SurahHuudA61-68.mp3|1990_p12R7SurahHuudA69-83.mp3|2000_p12R8SurahHuudA84-95.mp3|2010_p12R9SurahHuudA96-109.mp3|2020_p12R10SurahHuudA110-123.mp3|2030_p12R11SurahYusufA1-6.mp3|2040_p12R12SurahYusufA7-20.mp3|2050_p12R13SurahYusufA21-29.mp3|2060_p12R14SurahYusufA30-35.mp3|2065_p12R15SurahYusufA36-42.mp3|2066_p12R16SurahYusufA43-49.mp3|2067_p12R17SurahYusufA50-52.mp3|2070_p13R1SurahYusufA53-57.mp3|2080_p13R2SurahYusufA58-68.mp3|2090_p13R3SurahYusufA69-79.mp3|2100_p13R4SurahYusufA80-93.mp3|2110_p13R5SurahYusufA94-104.mp3|2120_p13R6SurahYusufA105-111.mp3|2130_p13R7SurahRadA1-7.mp3|2140_p13R8SurahRadA8-18.mp3|2150_p13R9SurahRadA19-26.mp3|2160_p13R10SurahRadA27-31.mp3|2170_p13R11SurahRadA32-37.mp3|2180_p13R12SurahRadA38-43.mp3|2190_p13R13SurahIbrahimA1-6.mp3|2200_p13R14SurahIbrahimA7-12.mp3|2210_p13R15SurahIbrahimA13-21.mp3|2220_p13R16SurahIbrahimA22-27.mp3|2230_p13R17SurahIbrahimA28-34.mp3|2240_p13R18SurahIbrahimA35-41.mp3|2250_p13R19SurahIbrahimA42-52.mp3|2260_p14R1SurahHijrA1-15.mp3|2270_p14R2SurahHijrA16-25.mp3|2280_p14R3SurahHijrA26-44.mp3|2290_p14R4SurahHijrA45-60.mp3|2300_p14R5SurahHijrA61-79.mp3|2310_p14R6SurahHijrA80-99.mp3|2320_p14R7SurahNahlA1-9.mp3|2330_p14R8SurahNahlA10-21.mp3|2340_p14R9SurahNahlA22-25.mp3|2350_p14R10SurahNahlA26-34.mp3|2360_p14R11SurahNahlA35-40.mp3|2370_p14R12SurahNahlA41-50.mp3|2380_p14R13SurahNahlA51-60.mp3|2390_p14R14SurahNahlA61-65.mp3|2400_p14R15SurahNahlA66-70.mp3|2410_p14R16SurahNahlA71-76.mp3|2420_p14R17SurahNahlA77-83.mp3|2430_p14R18SurahNahlA84-89.mp3|2440_p14R19SurahNahlA90-100.mp3|2450_p14R20SurahNahlA101-110.mp3|2460_p14R21SurahNahlA111-119.mp3|2470_p14R22SurahNahlA120-128.mp3|2475_p15R1SurahBaniIsraelA1-10.mp3|2476_p15R2SurahBaniIsraelA11-22.mp3|2477_p15R3SurahBaniIsraelA23-30.mp3|2478_p15R4SurahBaniIsraelA31-40.mp3|2479_p15R5SurahBaniIsraelA41-52.mp3|2480_p15R6SurahBaniIsraelA53-60.mp3|2481_p15R7SurahBaniIsraelA61-70.mp3|2482_p15R8SurahBaniIsraelA71-77.mp3|2483_p15R9SurahBaniIsraelA78-84.mp3|2484_p15R10SurahBaniIsraelA85-93.mp3|2485_p15R11SurahBaniIsraelA94-100.mp3|2486_p15R12SurahBaniIsraelA101-111.mp3|2487_p15R13SurahKahafA1-12.mp3|2490_p15R14SurahKahafA13-17.mp3|2500_p15R15SurahKahafA18-22.mp3|2510_p15R16SurahKahafA23-31.mp3|2520_p15R17SurahKahafA32-44.mp3|2530_p15R18SurahKahafA45-49.mp3|2540_p15R19SurahKahafA50-53.mp3|2550_p15R20SurahKahafA54-59.mp3|2560_p15R21SurahKahafA60-70.mp3|2570_p15R22SurahKahafA71-74.mp3|2700_p16R1SurahKahafA75-82.mp3|2710_p16R2SurahKahafA83-101.mp3|2720_p16R3SurahKahafA102-110.mp3|2730_p16R4SurahMaryamA1-15.mp3|2740_p16R5SurahMaryamA16-40.mp3|2750_p16R6SurahMaryamA41-50.mp3|2760_p16R7SurahMaryamA51-65.mp3|2770_p16R8SurahMaryamA66-82.mp3|2780_p16R9SurahMaryamA83-98.mp3|2790_p16R10SurahTahaA1-25.mp3|2800_p16R11SurahTahaA26-54.mp3|2810_p16R12SurahTahaA55-76.mp3|2820_p16R13SurahTahaA77-89.mp3|2830_p16R14SurahTahaA90-104.mp3|2840_p16R15SurahTahaA105-115.mp3|2850_p16R16SurahTahaA116-128.mp3|2860_p16R17SurahTahaA129-135.mp3|2870_p17R1SurahAn-mbiyaA1-10.mp3|2880_p17R2SurahAn-mbiyaA11-29.mp3|2890_p17R3SurahAn-mbiyaA30-41.mp3|2900_p17R4SurahAn-mbiyaA42-50.mp3|2910_p17R5SurahAn-mbiyaA51-75.mp3|2920_p17R6SurahAn-mbiyaA76-92.mp3|2930_p17R7SurahAn-mbiyaA93-112.mp3|2940_p17R8SurahHajjA1-10.mp3|2950_p17R9SurahHajjA11-22.mp3|2960_p17R10SurahHajjA23-25.mp3|2970_p17R11SurahHajjA26-33.mp3|2980_p17R12SurahHajjA34-38.mp3|2990_p17R13SurahHajjA39-48.mp3|3000_p17R14SurahHajjA49-57.mp3|3010_p17R15SurahHajjA58-64.mp3|3020_p17R16SurahHajjA65-72.mp3|3030_p17R17SurahHajjA73-78.mp3|3031_p18R1SurahMominoonA1-22.mp3|3032_p18R2SurahMominoonA23-32.mp3|3033_p18R3SurahMominoonA33-50.mp3|3034_p18R4SurahMominoonA51-77.mp3|3035_p18R5SurahMominoonA78-92.mp3|3040_p18R6SurahMominoonA93-118.mp3|3050_p18R7SurahNoorA1-10.mp3|3060_p18R8SurahNoorA11-20.mp3|3070_p18R9SurahNoorA21-26.mp3|3080_p18R10SurahNoorA27-34.mp3|3090_p18R11SurahNoorA35-40.mp3|3100_p18R12SurahNoorA41-50.mp3|3110_p18R13SurahNoorA51-57.mp3|3120_p18R14SurahNoorA58-61.mp3|3130_p18R15SurahNoorA62-64.mp3|3140_p18R16SurahFurqanA1-9.mp3|3150_p18R17SurahFurqanA10-20.mp3|3210_p19R01SurahFurqanA21-34.mp3|3220_p19R2SurahFurqanA35-44.mp3|3230_p19R3SurahFurqanA45-60.mp3|3240_p19R4SurahFurqanA61-77.mp3|3250_p19R5SurahShuaraA1-9.mp3|3260_p19R6SurahShuaraA10-33.mp3|3270_p19R7SurahShuaraA34-51.mp3|3280_p19R8SurahShuaraA52-68.mp3|3290_p19R9SurahShuaraA69-104.mp3|3300_p19R10SurahShuaraA105-121.mp3|3310_p19R11SurahShuaraA122-141.mp3|3320_p19R12SurahShuaraA142-159.mp3|3330_p19R13SurahShuaraA160-175.mp3|3340_p19R14SurahShuaraA176-191.mp3|3350_p19R15SurahShuaraA192-227.mp3|3360_p19R16SurahNamalA1-14.mp3|3370_p19R17SurahNamalA15-31.mp3|3380_p19R18SurahNamalA32-44.mp3|3390_p19R19SurahNamalA45-59.mp3|3400_p20R1SurahNamalA60-66.mp3|3410_p20R2SurahNamalA67-82.mp3|3420_p20R3SurahNamalA83-93.mp3|3430_p20R4SurahQasasA1-13.mp3|3440_p20R5SurahQasasA14-21.mp3|3450_p20R6SurahQasasA22-28.mp3|3460_p20R7SurahQasasA29-42.mp3|3470_p20R8SurahQasasA43-50.mp3|3480_p20R9SurahQasasA51-60.mp3|3490_p20R10SurahQasasA61-75.mp3|3500_p20R11SurahQasasA76-82.mp3|3510_p20R12SurahQasasA83-88.mp3|3520_p20R13SurahAnkabootA1-13.mp3|3530_p20R14SurahAnkabootA14-22.mp3|3540_p20R15SurahAnkabootA23-30.mp3|3550_p20R16SurahAnkabootA31-44.mp3|3650_p21R1SurahAnkabootA45-51.mp3|3660_p21R2SurahAnkabootA52-63.mp3|3670_p21R3SurahAnkabootA64-69.mp3|3680_p21R4SurahRoomA1-10.mp3|3690_p21R5SurahRoomA11-19.mp3|3700_p21R6SurahRoomA20-27.mp3|3710_p21R7SurahRoomA28-40.mp3|3720_p21R8SurahRoomA41-53.mp3|3730_p21R9SurahRoomA54-60.mp3|3740_p21R10SurahLuqmanA1-11.mp3|3741_p21R11SurahLuqmanA12-19.mp3|3742_p21R12SurahLuqmanA20-30.mp3|3743_p21R13SurahLuqmanA31-34.mp3|3744_p21R14SurahSajdahA1-11.mp3|3745_p21R15SurahSajdahA12-22.mp3|3746_p21R16SurahSajdahA23-30.mp3|3747_p21R17SurahAhzabA1-8.mp3|3748_p21R18SurahAhzabA9-20.mp3|3749_p21R19SurahAhzabA21-27.mp3|3750_p21R20SurahAhzabA28-30.mp3|3755_p22R1SurahAhzabA31-34.mp3|3760_p22R2SurahAhzabA35-40.mp3|3770_p22R3SurahAhzabA41-52.mp3|3775_p22R4SurahAhzabA53-58.mp3|3780_p22R5SurahAhzabA59-68.mp3|3790_p22R6SurahAhzabA69-73.mp3|3800_p22R7SurahSabaA1-9.mp3|3810_p22R8SurahSabaA10-21.mp3|3820_p22R9SurahSabaA22-30.mp3|3830_p22R10SurahSabaA31-36.mp3|3840_p22R11SurahSabaA37-45.mp3|3844_p22R12SurahSabaA46-54.mp3|3848_p22R13SurahFatirA1-7.mp3|3850_p22R14SurahFatirA8-14.mp3|3860_p22R15SurahFatirA15-26.mp3|3870_p22R16SurahFatirA27-37.mp3|3880_p22R17SurahFatirA38-45.mp3|3890_p22R18SurahYaseenA1-12.mp3|3900_p22R19SurahyaseenA13-21.mp3|3910_p23R1SurahYaseenA22-32.mp3|3920_p23R2SurahYaseenA33-50.mp3|3930_p23R3SurahYaseenA51-67.mp3|3940_p23R4SurahYaseenA68-83.mp3|3950_p23R5SurahSaaffatA1-21.mp3|3960_p23R6SurahSaaffatA22-74.mp3|3970_p23R7SurahSaaffatA75-113.mp3|3980_p23R8SurahSaaffatA114-138.mp3|3990_p23R9SurahSaaffatA139-182.mp3|4000_p23R10SurahSuaadA1-14.mp3|4010_p23R11SurahSuaadA15-26.mp3|4020_p23R12SurahSuaadA27-40.mp3|4030_p23R13SurahSuaadA41-64.mp3|4040_p23R14SurahSuaadA65-88.mp3|4050_p23R15SurahZumarA1-9.mp3|4060_p23R16SurahZumarA10-21.mp3|4070_p23R17SurahZumarA22-31.mp3|4075_p24R1SurahZumarA32-41.mp3|4076_p24R2SurahZumarA42-52.mp3|4077_p24R3SurahZumarA53-63.mp3|4078_p24R4SurahZumarA64-70.mp3|4080_p24R5SurahZumarA71-75.mp3|4090_p24R6SurahMuminA1-9.mp3|4100_p24R7SurahMuminA10-20.mp3|4110_p24R8SurahMuminA21-27.mp3|4120_p24R9SurahMuminA28-37.mp3|4130_p24R10SurahMuminA38-50.mp3|4140_p24R11SurahMuminA51-60.mp3|4150_p24R12SurahMuminA61-68.mp3|4160_p24R13SurahMuminA69-78.mp3|4170_p24R14SurahMuminA79-85.mp3|4180_p24R15HameemsajdahA1-8.mp3|4190_p24R16HameemsajdahA9-18.mp3|4200_p24R17HameemsajdahA19-25.mp3|4210_p24R18HameemsajdahA26-32.mp3|4220_p24R19HameemsajdahA33-44.mp3|4230_p24R20HameemsajdahA45-46.mp3|4280_p25R1HameemsajdahA47-54.mp3|4290_p25R2SurahShuraA1-9.mp3|4300_p25R3SurahShuraA10-19.mp3|4310_p25R4SurahShuraA20-29.mp3|4320_p25R5SurahShuraA30-43.mp3|4330_p25R6SurahShuraA44-53.mp3|4340_p25R7SurahZukhrufA1-15.mp3|4350_p25R8SurahZukhrufA16-25.mp3|4360_p25R9SurahZukhrufA26-35.mp3|4370_p25R10SurahZukhrufA36-45.mp3|4380_p25R11SurahZukhrufA46-56.mp3|4390_p25R12SurahZukhrufA57-67.mp3|4400_p25R13SurahZukhrufA68-89.mp3|4410_p25R14SurahDukhanA1-29.mp3|4420_p25R15SurahDukhanA30-43.mp3|4430_p25R16SurahDukhanA43-59.mp3|4440_p25R17SurahJasiahA1-11.mp3|4450_p25R18SurahJasiahA12-21.mp3|4460_p25R19SurahJasiahA22-26.mp3|4470_p25R20SurahJasiahA27-37.mp3|4520_p26R1SurahAhqafA1-10.mp3|4530_p26R2SurahAhqafA11-20.mp3|4540_p26R3SurahAhqafA21-26.mp3|4550_p26R4SurahAhqafA27-35.mp3|4560_p26R5SurahMuhammadA1-11.mp3|4570_p26R6SurahMuhammadA12-19.mp3|4580_p26R7SurahMuhammadA20-28.mp3|4590_p26R8SurahMuhammadA29-38.mp3|4600_p26R9SurahFatahA1-10.mp3|4610_p26R10SurahFatahA11-17.mp3|4620_p26R11SurahFatahA18-26.mp3|4630_p26R12SurahFatahA27-29.mp3|4640_p26R13SurahHujuratA1-10.mp3|4650_p26R14SurahHujuratA11-18.mp3|4660_p26R15SurahQaafA1-15.mp3|4665_p26R16SurahQaafA16-29.mp3|4666_p26R17SurahQaafA30-45.mp3|4667_p26R18SurahZariatA1-24.mp3|4668_p26R19SurahZariatA25-30.mp3|4670_p27R1SurahZariatA31-46.mp3|4680_p27R2SurahZariatA47-60.mp3|4690_p27R3SurahToorA1-28.mp3|4700_p27R4SurahToorA29-49.mp3|4710_p27R5SurahNajmA1-25.mp3|4720_p27R6SurahNajmA26-32.mp3|4730_p27R7SurahNajmA33-62.mp3|4740_p27R8SurahQamarA1-22.mp3|4750_p27R9SurahQamarA23-40.mp3|4760_p27R10SurahQamarA41-55.mp3|4770_p27R11SurahRahmanA1-25.mp3|4780_p27R12SurahRahmanA26-45.mp3|4790_p27R13SurahRahmanA46-78.mp3|4800_p27R14SurahWaqiaA1-38.mp3|4810_p27R15SurahWaqiaA39-74.mp3|4820_p27R16SurahWaqiaA75-96.mp3|4830_p27R17SurahHadeedA1-10.mp3|4840_p27R18SurahHadeedA11-19.mp3|4850_p27R19SurahHadeedA20-25.mp3|4860_p27R20SurahHadeedA26-29.mp3|4870_p28R1SurahMujadalahA1-6.mp3|4880_p28R2SurahMujadalahA7-13.mp3|4890_p28R3SurahMujadalahA14-22.mp3|4900_p28R4SurahHashrA1-10.mp3|4910_p28R5SurahHashrA11-17.mp3|4920_p28R6SurahHashrA18-24.mp3|4930_p28R7SurahMumtahinaA1-6.mp3|4940_p28R8SurahMumtahinaA7-13.mp3|4950_p28R9SurahSaffA1-9.mp3|4960_p28R10SurahSaffA10-14.mp3|4970_p28R11SurahJumuaA1-8.mp3|4980_p28R12SurahJumuaA9-11.mp3|4990_p28R13SurahMunafiqoonA1-8.mp3|5000_p28R14SurahMunafiqoonA9-11.mp3|5010_p28R15SurahTaghabunA1-10.mp3|5020_p28R16SurahTaghabunA11-18.mp3|5030_p28R17SurahTalaqA1-7.mp3|5040_p28R18SurahTalaqA8-12.mp3|5050_p28R19SurahTehreemA1-7.mp3|5060_p28R20SurahTehreemA8-12.mp3|5175_p29R1SurahMulkA1-14.mp3|5176_p29R2SurahMulkA15-30.mp3|5177_p29R3SurahQalamA1-33.mp3|5178_p29R4SurahQalamA34-52.mp3|5179_p29R5SurahHaqqahA1-37.mp3|5180_p29R6SurahHaqqahA38-52.mp3|5181_p29R7SurahMaarijA1-35.mp3|5182_p29R8SurahMaarijA36-44.mp3|5183_p29R9SurahNoohA1-20.mp3|5184_p29R10SurahNoohA21-28.mp3|5185_p29R11SurahJinA1-19.mp3|5186_p29R12SurahJinA20-28.mp3|5187_p29R13SurahMuzzammilA1-19.mp3|5188_p29R14SurahMuzzammilA20.mp3|5189_p29R15SurahMuddassirA1-31.mp3|5190_p29R16SurahMuddassirA32-56.mp3|5191_p29R17SurahQiyamahA1-30.mp3|5192_p29R18SurahQiyamahA31-40.mp3|5193_p29R19SurahDahrA1-22.mp3|5194_p29R20SurahDahrA23-31.mp3|5195_p29R21SurahMursalatA1-40.mp3|5196_p29R22SurahMursalatA41-50.mp3|5290_p30R1SurahNabaA1-30.mp3|5300_p30R2SurahNabaA31-40.mp3|5310_p30R3SurahNaziatA1-26.mp3|5320_p30R4SurahNaziatA27-46.mp3|5330_p30R5SurahAbasA1-42.mp3|5340_p30R6SurahTakweerA1-29.mp3|5350_p30R7SurahInfitarA1-19.mp3|5360_p30R8SurahMutaffifeenA1-36.mp3|5370_p30R9SurahInshiqaqA1-25.mp3|5380_p30R10SurahBuroojA1-22.mp3|5390_p30R11SurahTariqA1-17.mp3|5400_p30R12SurahAalaA1-19.mp3|5410_p30R13SurahGashiaA1-26.mp3|5420_p30R14SurahFajrA1-30.mp3|5430_p30R15SurahBaladA1-20.mp3|5440_p30R16SurahShamsA1-15.mp3|5450_p30R17SurahLailA1-21.mp3|5460_p30R18SurahDuhaA1-11.mp3|5470_p30R19SurahInshrahA1-8.mp3|5480_p30R20SurahTeenA1-8.mp3|5490_p30R21SurahAlaqA1-19.mp3|5500_p30R22SurahQadrA1-5.mp3|5510_p30R23SurahBayyinatA1-8.mp3|5520_p30R24SurahZilzalA1-8.mp3|5530_p30R25SurahAdiyatA1-11.mp3|5540_p30R26SurahQariaA1-11.mp3|5550_p30R27SurahTakasurA1-8.mp3|5560_p30R28SurahAsrA1-3.mp3|5570_p30R29SurahHumazahA1-9.mp3|5580_p30R30SurahFeelA1-5.mp3|5590_p30R31SurahQuraushA1-4.mp3|5600_p30R32SurahMaoonA1-7.mp3|5610_p30R33SurahKauserA1-3.mp3|5620_p30R34SurahKafiroonA1-6.mp3|5630_p30R35SurahNasrA1-3.mp3|5640_p30R36SurahLahabA1-5.mp3|5650_p30R37SurahIkhlasA1-4.mp3|5660_p30R38SurahFalaqA1-5.mp3|5670_p30R39SurahNaasA1-6.mp3|5994_dua.mp3"},
{n="Tafseer of Quran English - Dr. Israr Ahmed (113 Parts)", l="English", i="Dr.IsrarAhmedEnglishTafsirFullQuran", s="bk_eng_israr113", p="Dr. Israr Ahmed - Tafseer of Quran English %03dof113.mp3", nf=113},
{n="Riyad-us-Saliheen English Audiobook (372 Chapters)", l="English", i="riyad-us-saliheen_202411", s="bk_eng_riyad372", p="%03d.mp3", nf=372},
{n="40 Hadith Masjid English (42 Hadith)", l="English", i="40-hadith-masjid-english", s="bk_eng_40hadith", d="Hadith 1.mp3|Hadith 10.mp3|Hadith 11.mp3|Hadith 12.mp3|Hadith 13.mp3|Hadith 14.mp3|Hadith 15.mp3|Hadith 16.mp3|Hadith 17.mp3|Hadith 18.mp3|Hadith 19.mp3|Hadith 2.mp3|Hadith 20.mp3|Hadith 21.mp3|Hadith 22.mp3|Hadith 23.mp3|Hadith 24.mp3|Hadith 25.mp3|Hadith 26.mp3|Hadith 27.mp3|Hadith 28.mp3|Hadith 29.mp3|Hadith 3.mp3|Hadith 30.mp3|Hadith 31.mp3|Hadith 32.mp3|Hadith 33.mp3|Hadith 34.mp3|Hadith 35.mp3|Hadith 36.mp3|Hadith 37.mp3|Hadith 38.mp3|Hadith 39.mp3|Hadith 4.mp3|Hadith 40.mp3|Hadith 41.mp3|Hadith 42.mp3|Hadith 5.mp3|Hadith 6.mp3|Hadith 7.mp3|Hadith 8.mp3|Hadith 9.mp3"},
{n="Islamic Guidance - Short Reminders (77 Clips)", l="English", i="way_169", s="bk_eng_reminders", d="1 (1).mp3|1 (10).mp3|1 (11).mp3|1 (12).mp3|1 (13).mp3|1 (14).mp3|1 (15).mp3|1 (16).mp3|1 (17).mp3|1 (18).mp3|1 (19).mp3|1 (2).mp3|1 (20).mp3|1 (21).mp3|1 (22).mp3|1 (23).mp3|1 (24).mp3|1 (25).mp3|1 (26).mp3|1 (27).mp3|1 (28).mp3|1 (29).mp3|1 (3).mp3|1 (30).mp3|1 (31).mp3|1 (32).mp3|1 (33).mp3|1 (34).mp3|1 (35).mp3|1 (36).mp3|1 (37).mp3|1 (38).mp3|1 (39).mp3|1 (4).mp3|1 (40).mp3|1 (41).mp3|1 (42).mp3|1 (43).mp3|1 (44).mp3|1 (45).mp3|1 (46).mp3|1 (47).mp3|1 (48).mp3|1 (49).mp3|1 (5).mp3|1 (50).mp3|1 (51).mp3|1 (52).mp3|1 (53).mp3|1 (54).mp3|1 (55).mp3|1 (56).mp3|1 (57).mp3|1 (58).mp3|1 (59).mp3|1 (6).mp3|1 (60).mp3|1 (61).mp3|1 (62).mp3|1 (63).mp3|1 (64).mp3|1 (65).mp3|1 (66).mp3|1 (67).mp3|1 (68).mp3|1 (69).mp3|1 (7).mp3|1 (70).mp3|1 (71).mp3|1 (72).mp3|1 (73).mp3|1 (74).mp3|1 (75).mp3|1 (76).mp3|1 (77).mp3|1 (8).mp3|1 (9).mp3"},
{n="Usul-ul-Hadith English (10 Parts)", l="English", i="usul-ul-hadith-in-english-audio", s="bk_eng_usul10", d="01 usul_al_hadith_part_01.mp3|02 usul_al_hadith_part_02.mp3|03 usul_al_hadith_part_03.mp3|04 usul_al_hadith_part_04.mp3|05 usul_al_hadith_part_05.mp3|06 usul_al_hadith_part_06.mp3|07 sciences_of_hadith_part_01.mp3|08 sciences_of_hadith_part_02.mp3|09 defense_of_the_sunnah_part_01.mp3|10 defense_of_the_sunnah_part_02.mp3"},
{n="Life of Prophet Muhammad - Makkah Period (16 Parts)", l="English", i="TheLifeOfTheProphetMuhammadMakaPeriod", s="bk_eng_makka16", d="01-Introduction.mp3|02-BackgroundHistory.mp3|03-TheReligiousSituationOfPre-islamicArabia.mp3|04-EarlyLife.mp3|05-ImportantEvents.mp3|06-InPursuitOfTheTruth.mp3|07-TheGladTidings.mp3|08-TheRevelation.mp3|09-TheReactionPart1.mp3|10-TheReactionPart2.mp3|11-TheEarlyImmigrantsPart1.mp3|12-TheEarlyImmigrantsPart2.mp3|13-MajorEvents.mp3|14-TheLaterYearsOfMakkah.mp3|15-InSearchOfABase.mp3|16-TheRoadToMadinah.mp3"},
{n="Sahih Muslim English Audiobook - Book-wise (56 Books)", l="English", i="sahih_muslim_202411", s="bk_eng_sahihmuslim56", d="Sahih Muslim  Book 00 The Book of Narrating from the Trustworthy  Hadith 1-92 of 7563 English.mp3|Sahih Muslim  Book 01 The Book Of Faith  Hadith 93-533 of 7563 English.mp3|Sahih Muslim  Book 02 The Book Of Purification  Hadith 534-678 of 7563 English.mp3|Sahih Muslim  Book 03 The Book Of Menstruation  Hadith 679-836 of 7563 English.mp3|Sahih Muslim  Book 04 The Book Of Prayer  Hadith 837-1160 of 7563 English.mp3|Sahih Muslim  Book 05 Book of Masajid & Places Of Prayer  Hadith 1161-1559 of 7563 English.mp3|Sahih Muslim  Book 06 Book Of The Travellers' Prayer & Shortening Thereof  Hadith 1570-1836 of 7563 English.mp3|Sahih Muslim  Book 06A The book of the virtues of the Quran  Hadith 1837-1950 English.mp3|Sahih Muslim  Book 07 The Book Of Jumuah (Friday) Prayer  Hadith 1951-2043 English.mp3|Sahih Muslim  Book 08 Book Of The Two id Prayers  Hadith 2044-2069 of 7563 English.mp3|Sahih Muslim  Book 09 Prayer Seeking Rain (Al-Istisqâ')  Hadith 2070-2088 English.mp3|Sahih Muslim  Book 10 The Book Of Eclipses  Hadith 2089-2122 of 7563 English.mp3|Sahih Muslim  Book 11 The Book Of Funerals  Hadith 2123-2262 of 7563 English.mp3|Sahih Muslim  Book 12 The Book Of Zakat  Hadith 2263-2494 of 7563 English.mp3|Sahih Muslim  Book 13 The Book Of Fasting  Hadith 2495-2779 of 7563 English.mp3|Sahih Muslim  Book 14 The Book Of Itikaf  Hadith 2780-2790 of 7563 English.mp3|Sahih Muslim  Book 15 Book Of Hajj (Pilgrimage)  Hadith 2791-3397 of 7563 English.mp3|Sahih Muslim  Book 16 The Book Of Marriage  Hadith 3398-3567 of 7563 English.mp3|Sahih Muslim  Book 17 The Book Of Breastfeeding  Hadith 3568-3651 of 7563 English.mp3|Sahih Muslim  Book 18 The Book Of Divorce  Hadith 3652-3742 of 7563 English.mp3|Sahih Muslim  Book 19 Book Of Lian (Mutual cursing)  Hadith 3743-3769 of 7563 English.mp3|Sahih Muslim  Book 20 The Book Of Manumission  Hadith 3770-3800 of 7563 English.mp3|Sahih Muslim  Book 21 Book Of Financial Transactions  Hadith 3801-3961 of 7563 English.mp3|Sahih Muslim  Book 22 Musaqa & Muamalah (agricultural contract  Hadith 3962-4139 English.mp3|Sahih Muslim  Book 23 The Shares Of Inheritance  Hadith 4140-4162 of 7563 English.mp3|Sahih Muslim  Book 24 The Book Of Gifts  Hadith 4163-4203 of 7563 English.mp3|Sahih Muslim  Book 25 The Book Of Wills  Hadith 4204-4234 of 7563 English.mp3|Sahih Muslim  Book 26 The Book Of Vows  Hadith 4235-4253 of 7563 English.mp3|Sahih Muslim  Book 27 The Book Of Oaths  Hadith 4254-4341 of 7563 English.mp3|Sahih Muslim  Book 28 Oaths, Retaliation & Blood Money  Hadith 4342-4397 English.mp3|Sahih Muslim  Book 29 Hudud (Legal Punishments)  Hadith 4398-4469 of 7563 English.mp3|Sahih Muslim  Book 30 The Book Of Judicial Decisions  Hadith 4470-4497 of 7563 English.mp3|Sahih Muslim  Book 31 The Book Of Lost Property  Hadith 4498-4518 of 7563 English.mp3|Sahih Muslim Book 32 The Book Of Jihad And Expeditions  Hadith 4519-4700 of 7563 English.mp3|Sahih Muslim Book 33  The Book of Leadership  Hadith 4701-4971 of 7563 English.mp3|Sahih Muslim Book 34  The Book of Hunting, Slaughter And What Animals May Be Eaten Hadith 4972-5063 English.mp3|Sahih Muslim Book 35  The Book of Sacrifices  Hadith 5064-5129 of 7563 English.mp3|Sahih Muslim Book 36  The Book of Drinks  Hadith 5127-5384 of 7563 English.mp3|Sahih Muslim Book 37  The Book of Clothing And Adornment  Hadith 5385-5585 of 7563 English.mp3|Sahih Muslim Book 38  The Book Of Al Adab (Manners And Etiquette) Hadith 5586-5645 of 7563 English.mp3|Sahih Muslim Book 39  The Book of The Salam (Greeting)  Hadith 5646-5861 of 7563 English.mp3|Sahih Muslim Book 40  The Book of Manners And Use of Correct Words  Hadith 5862-5884 of 7563 English.mp3|Sahih Muslim Book 41  The Book Of Poetry  Hadith 5885-5896 of 7563 English.mp3|Sahih Muslim Book 42  The Book Of Dreams  Hadith 5897-5937 of 7563 English.mp3|Sahih Muslim Book 43  The Book Of Virtues  Hadith 5938-6168 of 7563 English.mp3|Sahih Muslim Book 44  The Book Of The Virtues Of The Companions  Hadith 6169-6499 of 7563 English.mp3|Sahih Muslim Book 45  The Book Of Virtues, Nurturing Ties And Manners  Hadith 6500-6722 of 7563 English.mp3|Sahih Muslim Book 46  The Book Of Al-Qadr (The Divine Decree)  Hadith 6723-6774 of 7563 English.mp3|Sahih Muslim Book 47  The Book Of Knowledge  Hadith 6775-6804 of 7563 English.mp3|Sahih Muslim Book 48  Remembrance, Supplication, Repentance & Praying For Forgiveness Hadith 6805-6951 English.mp3|Sahih Muslim Book 49  The Book Of Repentance  Hadith 6952-7023 of 7563 English.mp3|Sahih Muslim Book 50  The Attributes Of The Hypocrites & The Rulings Concerning Them Hadith 7024-7129 English.mp3|Sahih Muslim Book 51  The Book Of Paradise & Description Of Its Delights & Its People Hadith 7130-7234 English.mp3|Sahih Muslim Book 52  The Book Of Tribulations & The Portents Of The Hour  Hadith 7235-7416 of7563 English.mp3|Sahih Muslim Book 53  The Book Of Asceticism (Az-Zuhd) & Heart Softening Reports Hadith 7417-7522of 7563 English.mp3|Sahih Muslim Book 54  The Book Of Tafsir (Explanation Of Quran)  Hadith 7523-7563 of 7563 English.mp3"},
{n="Quran English Tafsir - Muhsin Khan (114 Surah)", l="English", i="complete-quran-english-tafsir-audio-muhsin-khan", s="bk_eng_muhsin114", d="001-Al-fatiha.mp3|002-Al-baqarah.mp3|003-Aal-e-imraan.mp3|004-An-nisaa.mp3|005-Al-maaida.mp3|006-Al-anaam.mp3|007-Al-araaf.mp3|008-Al-anfaal.mp3|009-At-taubah.mp3|010-Yoonus.mp3|011-Hud.mp3|012-Yoosuf.mp3|013-Ar-rad.mp3|014-Ibraheem.mp3|015-Al-hijr.mp3|016-An-nahl.mp3|017-Al-israa.mp3|018-Al-kahf.mp3|019-Maryam.mp3|020-Ta-ha.mp3|021-Al-anbiyaa.mp3|022-Al-hajj.mp3|023-Al-muminoon.mp3|024-An-noor.mp3|025-Al-furqaan.mp3|026-Ash-shuaraa.mp3|027-An-naml.mp3|028-Al-qasas.mp3|029-Al-ankaboot.mp3|030-Ar-room.mp3|031-Luqmaan.mp3|032-As-sajdah.mp3|033-Al-ahzaab.mp3|034-Saba.mp3|035-Faatir.mp3|036-Ya-seen.mp3|037-As-saaffaat.mp3|038-Saad.mp3|039-Az-zumar.mp3|040-Ghaafiral-mumin.mp3|041-Fussilatha-meem.mp3|042-Ash-shoora.mp3|043-Az-zukhruf.mp3|044-Ad-dukhaan.mp3|045-Al-jaathiya.mp3|046-Al-ahqaaf.mp3|047-Muhammadsaas.mp3|048-Al-fath.mp3|049-Al-hujuraat.mp3|050-Qaaf.mp3|051-Adh-dhaariyaat.mp3|052-At-toor.mp3|053-An-najm.mp3|054-Al-qamar.mp3|055-Ar-rahmaan.mp3|056-Al-waaqia.mp3|057-Al-hadeed.mp3|058-Al-mujaadila.mp3|059-Al-hashr.mp3|060-Al-mumtahana.mp3|061-As-saff.mp3|062-Al-jumua.mp3|063-Al-munaafiqoon.mp3|064-At-taghaabun.mp3|065-At-talaq.mp3|066-At-tahreem.mp3|067-Al-mulk.mp3|068-Al-qalam.mp3|069-Al-haaqqah.mp3|070-Al-maaarij.mp3|071-Nooh.mp3|072-Al-jinn.mp3|073-Al-muzzammil.mp3|074-Al-muddaththir.mp3|075-Al-qiyaamah.mp3|076-Al-insaanad-dahr.mp3|077-Al-mursalat.mp3|078-An-naba.mp3|079-An-naaziaat.mp3|080-abasa.mp3|081-At-takweer.mp3|082-Al-infitaar.mp3|083-Al-mutaffifeen.mp3|084-Al-inshiqaaq.mp3|085-Al-burooj.mp3|086-At-taariq.mp3|087-Al-ala.mp3|088-Al-ghaashiya.mp3|089-Al-fajr.mp3|090-Al-balad.mp3|091-Ash-shams.mp3|092-Al-layl.mp3|093-Ad-duha.mp3|094-Al-inshirahash-sharh.mp3|095-At-teen.mp3|096-Al-alaq.mp3|097-Al-qadr.mp3|098-Al-bayyinah.mp3|099-Az-zalzalah.mp3|100-Al-aadiyaat.mp3|101-Al-qaaria.mp3|102-At-takaathur.mp3|103-Al-asr.mp3|104-Al-humaza.mp3|105-Al-feel.mp3|106-Quraysh.mp3|107-Al-maaoon.mp3|108-Al-kawthar.mp3|109-Al-kaafiroon.mp3|110-An-nasr.mp3|111-Al-masadal-lahab.mp3|112-Al-ikhlas.mp3|113-Al-falaq.mp3|114-An-naas.mp3"},
{n="Quran with English Translation - Mishary Rashid (115 Files)", l="English", i="Quran_With_English_Translation", s="bk_eng_mishary115", d="001 surah_al_fatihah.mp3|002 surah_al_baqarah.mp3|003 surah_al_imran.mp3|004 surah_an_nisa.mp3|005 surah_al_maidah.mp3|006 surah_al_anam.mp3|007 surah_al_araf.mp3|008 surah_al_anfal.mp3|009 surah_at_tawbah.mp3|010 surah_yunus.mp3|011 surah_hud.mp3|012 surah_yusuf.mp3|013 surah_ar_rad.mp3|014 surah_ibrahim.mp3|015 surah_al_hijr.mp3|016 surah_an_nahl.mp3|017 surah_al_isra.mp3|018 surah_al_kahf.mp3|019 surah_maryam.mp3|020 surah_ta_ha.mp3|021 surah_al_anbiya.mp3|022 surah_al_hajj.mp3|023 surah_al_muminun.mp3|024 surah_an_nur.mp3|025 surah_al_furqan.mp3|026 surah_ash_shuara.mp3|027 surah_an_naml.mp3|028 surah_al_qasas.mp3|029 surah_al_ankabut.mp3|030 surah_ar_rum.mp3|031Surah_luqman.mp3|032Surah_as_sajdah.mp3|033Surah_al_ahzab.mp3|034Surah_saba.mp3|035Surah_fatir.mp3|036Surah_ya_sin.mp3|037Surah_as_safat.mp3|038Surah_sad.mp3|039Surah_az_zumar.mp3|040Surah_ghafir.mp3|041Surah_fussilat.mp3|042Surah_ash_shura.mp3|043Surah_az_zukhruf.mp3|044Surah_ad_dukhan.mp3|045Surah_al_jathiyah.mp3|046Surah_al_ahqaf.mp3|047Surah_muhammad.mp3|048Surah_al_fath.mp3|049Surah_al_hujurat.mp3|050Surah_qaf.mp3|051Surah_adh_dhariyat.mp3|052Surah_at_tur.mp3|053Surah_an_najm.mp3|054Surah_al_qamar.mp3|055Surah_ar_rahman.mp3|056Surah_al_waqiah.mp3|057Surah_al_hadid.mp3|058Surah_al_mujadilah.mp3|059Surah_al_hashr.mp3|060Surah_al_mumtahanah.mp3|061Surah_as_saff.mp3|062Surah_al_jumuah.mp3|063Surah_al_munafiqun.mp3|064Surah_at_taghabun.mp3|065Surah_at_talaq.mp3|066Surah_at_tahrim.mp3|067Surah_al_mulk.mp3|068Surah_al_qalam.mp3|069Surah_al_haqqah.mp3|070Surah_al_maarij.mp3|071Surah_nuh.mp3|072Surah_al_jinn.mp3|073Surah_al_muzzammil.mp3|074Surah_al_muddaththir.mp3|075Surah_al_qiyamah.mp3|076Surah_al_insan.mp3|077Surah_al_mursalat.mp3|078Surah_an_naba.mp3|079Surah_an_naziat.mp3|080Surah_abasa.mp3|081Surah_at_takwir.mp3|082Surah_al_infitar.mp3|083Surah_al_mutaffifin.mp3|084Surah_al_inshiqaq.mp3|085Surah_al_buruj.mp3|086Surah_at_tariq.mp3|087Surah_al_ala.mp3|088Surah_al_ghashiyah.mp3|089Surah_al_fajr.mp3|090Surah_al_balad.mp3|091Surah_ash_shams.mp3|092Surah_al_layl.mp3|093Surah_ad_duha.mp3|094Surah_ash_sharh.mp3|095Surah_at_tin.mp3|096Surah_al_alaq.mp3|097Surah_al_qadr.mp3|098Surah_al_bayyinah.mp3|099Surah_az_zalzalah.mp3|100Surah_al_adiyat.mp3|101Surah_al_qariah.mp3|102Surah_at_takathur.mp3|103Surah_al_asr.mp3|104Surah_al_humazah.mp3|105Surah_al_fil.mp3|106Surah_quraysh.mp3|107Surah_al_maun.mp3|108Surah_al_kawthar.mp3|109Surah_al_kafirun.mp3|110Surah_an_nasr.mp3|111Surah_al_masad.mp3|112Surah_al_ikhlas.mp3|113Surah_al_falaq.mp3|114Surah_an_nas.mp3|Juz-Amma.mp3"},
{n="Quran Kamil - Mahmoud Khalil Al-Husary (Arabic, 114 Surah)", l="Arabic", i="aldiaa-quran-husary", s="bk_ar_husary", p="%03d.mp3", nf=114},
{n="Quran Kamil - Saad Al-Ghamdi (Arabic, 114 Surah)", l="Arabic", i="aldiaa-quran-ghamadi", s="bk_ar_ghamdi", p="%03d.mp3", nf=114},
{n="Quran Kamil - Mohamed Siddiq Al-Minshawi (Arabic, 114 Surah)", l="Arabic", i="aldiaa-quran-minshawy", s="bk_ar_minshawi", p="%03d.mp3", nf=114},
{n="Quran Kamil - Ahmed Al-Ajmy (Arabic, 114 Surah)", l="Arabic", i="aldiaa-quran-ajmy", s="bk_ar_ajmy", p="%03d.mp3", nf=114},
{n="Quran Kamil - Mishary Rashid Alafasy (Arabic, 114 Surah)", l="Arabic", i="aldiaa-quran-afasy", s="bk_ar_afasy", p="%03d.mp3", nf=114},
{n="Quran Kamil - Maher Al-Muaiqly (Arabic, 114 Surah)", l="Arabic", i="aldiaa-quran-muaiqly", s="bk_ar_muaiqly", p="%03d.mp3", nf=114},
{n="Quran Kamil - Abdul Basit Abdus-Samad (Arabic, 114 Surah)", l="Arabic", i="aldiaa-quran-abdulbasit", s="bk_ar_abdulbasit", p="%03d.mp3", nf=114},
{n="Quran Kamil - Mohammad Hosyn Amer (Arabic, 114 Surah)", l="Arabic", i="mohammad-hosyn-3amer", s="bk_ar_hosyn", p="mohammad-hosyn-3amer/%03d.mp3", nf=114},
{n="Quran Kamil (Warsh) - Rachid Belaalih (Arabic, 114 Surah)", l="Arabic", i="rashid_Belaalih", s="bk_ar_belaalih", p="rachid_Belaalih/%03d.mp3", nf=114},
{n="Naatein - Famous Naat Khawans (638 Naats)", l="Urdu", i="NaatsOfRasool-Ul-ALLAHNaatsFromFamousNaatKhawans", s="bk_naats_famous638", c="naat", d="001AllahMereAllah-FarhanAliQadri.mp3|002HumKoBulanaYaRasool-farhanAliQadri.mp3|003KabeKiRonak-farhanAliQadri.mp3|004KehtiHeYaPhoolon-farhanAliQadri.mp3|005KesaLageGa-farhanAliQadri.mp3|006MeraWalionKeImam-farhanAliQadri.mp3|007MeriDarkhanMe-farhanAliQadri.mp3|008MitheMadniKesiraiki-farhanAliQadri.mp3|009TumhraJodibangali-farhanAliQadri.mp3|010AllahNabiDaNaam-farhanAliQadri.mp3|011DamBaDumAllahHoo-farhanAliQadri.mp3|012HarPeghamarDaUhda-farhanAliQadri.mp3|013JannatMainLekar-farhanAliQadri.mp3|014KahoKeNara-farhanAliQadri.mp3|015LabPeNaatENabi-farhanAliQadri.mp3|016LikhRahaHooNaat-farhanAliQadri.mp3|017MadinaMadina-farhanAliQadri.mp3|018MainLajpaalDe-farhanAliQadri.mp3|019MithoPyaro-farhanAliQadri.mp3|020HaqAllah-farhanAliQadri.mp3|021JashneyAmadeyRasool-farhanAliQadri.mp3|022MarhabaYaMustafa-farhanAliQadri.mp3|023MereAaqaAyeJuhmoo-farhanAliQadri.mp3|024NoorWalaAyaHai-farhanAliQadri.mp3|025ShehanShaheyWalaKiAmad-farhanAliQadri.mp3|026TereGeetGawanYaRasoolAllah-farhanAliQadri.mp3|027YaRabMeri-farhanAliQadri.mp3|028ZikareyKhudaMein-farhanAliQadri.mp3|029AisaTujhe-fazlayAhmedRaza.mp3|030AjabRangPerHai-fazlayAhmedRaza.mp3|031AkashGumbadeKhizra-fazlayAhmedRaza.mp3|032Hamd-fazlayAhmedRaza.mp3|033Aujalaaujalakiyahaynabinay-ghulamMustafaAttari.mp3|034Ayraheemaykareem-ghulamMustafaAttari.mp3|035Hambhykaheinyanabitumbhykahoyanabi-ghulamMustafaAttari.mp3|036Maulaalimushkilkushahein-ghulamMustafaAttari.mp3|037Merayhuzoorsasahibejamalkoienahy-ghulamMustafaAttari.mp3|038Sotaysotaymeinnaatepaakparhyhaykabhykabhy-ghulamMustafaAttari.mp3|039Terakaramchaheye-ghulamMustafaAttari.mp3|040Terakiabannaygabanday-ghulamMustafaAttari.mp3|041Yarasoolallahhumterayhein-ghulamMustafaAttari.mp3|042Allah-sohneya-hafizAhmedRaza.mp3|043AssalamYaaNabiwithoutDaff-HafizAhmadRazaQadriNew-hafizAhmedRaza.mp3|044Bula-lo-ya-rasoolallah-hafizAhmedRaza.mp3|045Hasbi-rabi-jal-allah-hafizAhmedRaza.mp3|046Hum-par-ho-khudaya-hafizAhmedRaza.mp3|047Jiyo-ishq-main-hafizAhmedRaza.mp3|048Karta-hu-touba-hafizAhmedRaza.mp3|049Khair-pa-de-hafizAhmedRaza.mp3|050Maula-ali-hafizAhmedRaza.mp3|051Mere-nabi-da-ishq-hafizAhmedRaza.mp3|052Nabi-ke-deewane-hafizAhmedRaza.mp3|053Sab-se-aula-o-aala-hafizAhmedRaza.mp3|054Subhan-allah-hafizAhmedRaza.mp3|055YaMuhammadNoorEMujassamAndIshqKayRangMainRangJao-hafizAhmedRaza.mp3|056Ya-shah-e-umam-hafizAhmedRaza.mp3|057Allah_allah_allah_hoo-hafizSerwerSoharwardi.mp3|058Hamhain_aksar_madinay-hafizSerwerSoharwardi.mp3|059Ya_nabi_dekha_ye_rutba-hafizSerwerSoharwardi.mp3|060Allahterashukarhay-hafizNisarAhmedMarfani.mp3|061Aminakalaalaaya-hafizNisarAhmedMarfani.mp3|062Dilmeinhogarhoishqsacha-hafizNisarAhmedMarfani.mp3|063Ediaayenoorki-hafizNisarAhmedMarfani.mp3|064Farishtayjiskayzaairhein-hafizNisarAhmedMarfani.mp3|065Sadijholiwichrahmatda-hafizNisarAhmedMarfani.mp3|066Unkarozadekhloon-hafizNisarAhmedMarfani.mp3|067Wiladatkaytaranay-hafizNisarAhmedMarfani.mp3|068Yarasoolallahkaramhai-hafizNisarAhmedMarfani.mp3|069Ahista_chal1-hafizNisarAhmedMarfani.mp3|070Ahista_chal-hafizNisarAhmedMarfani.mp3|071Ajabkaram-hafizNisarAhmedMarfani.mp3|072Alif_allah-hafizNisarAhmedMarfani.mp3|073Allah_hoo_allah_hoo-hafizNisarAhmedMarfani.mp3|074Allah_ne_pohanchaya_sarkar-hafizNisarAhmedMarfani.mp3|075Allahkaram_moulakaram-hafizNisarAhmedMarfani.mp3|076Apna_damane_shafat-hafizNisarAhmedMarfani.mp3|077Apnay_darka_mujhko-hafizNisarAhmedMarfani.mp3|078Aya_na_hoga_isterha-hafizNisarAhmedMarfani.mp3|079Bakht_khufta_ne-hafizNisarAhmedMarfani.mp3|080Bas_yehi_tamana_hay-hafizNisarAhmedMarfani.mp3|081Bigribanao-hafizNisarAhmedMarfani.mp3|082Chamak_tujhse_patay-hafizNisarAhmedMarfani.mp3|083Chamaktujhsepatayhian-hafizNisarAhmedMarfani.mp3|084Dare_nabi_pe_ye_umar-hafizNisarAhmedMarfani.mp3|085Dildard_se_bismil-hafizNisarAhmedMarfani.mp3|086Gunahon_ki_adat-hafizNisarAhmedMarfani.mp3|087Guzray_jo_wahan-hafizNisarAhmedMarfani.mp3|088Ham_hain_iltija_walay-hafizNisarAhmedMarfani.mp3|089Hamne_marnay_ki_madinay-hafizNisarAhmedMarfani.mp3|090Itna_milta_hay_kay_hisab-hafizNisarAhmedMarfani.mp3|091Jaaigi_hanstihovi_khuldmain-hafizNisarAhmedMarfani.mp3|092Jitna_meray_khuda_ko-hafizNisarAhmedMarfani.mp3|093Kabay_kay_samne-hafizNisarAhmedMarfani.mp3|094Kitnay_haseen_tasawur-hafizNisarAhmedMarfani.mp3|095Kuch_aisa_kardey_meray-hafizNisarAhmedMarfani.mp3|096Madinay_jakay_madinay2-hafizNisarAhmedMarfani.mp3|097Madinay_jakay_madinay-hafizNisarAhmedMarfani.mp3|098Madinay_kay_wali-hafizNisarAhmedMarfani.mp3|099Mahe_taiba-hafizNisarAhmedMarfani.mp3|100Main_madinay_chala-hafizNisarAhmedMarfani.mp3|101Main_to_panjatan-hafizNisarAhmedMarfani.mp3|102Marhaba_ya_mustafa-hafizNisarAhmedMarfani.mp3|103Mazhareshane-hafizNisarAhmedMarfani.mp3|104Muhammad_mustafa_noore-hafizNisarAhmedMarfani.mp3|105Mujhaybhimadinay-hafizNisarAhmedMarfani.mp3|106Munawar_mery_ankhoun-hafizNisarAhmedMarfani.mp3|107Mustafa_jane_rehmatpe-hafizNisarAhmedMarfani.mp3|108Panjatankagulam-hafizNisarAhmedMarfani.mp3|109Phirkaygaligali-hafizNisarAhmedMarfani.mp3|110Pukaro_yarasollah-hafizNisarAhmedMarfani.mp3|111Rehmat_baras_rahi_hay-hafizNisarAhmedMarfani.mp3|112Rukhdin_hay_ya_mehray-hafizNisarAhmedMarfani.mp3|113Salam_tajdare_haram-hafizNisarAhmedMarfani.mp3|114Sarkar_ghoue_azam-hafizNisarAhmedMarfani.mp3|115Sarkaryenaam-hafizNisarAhmedMarfani.mp3|116Subah_taiba_main_hovi-hafizNisarAhmedMarfani.mp3|117Sukoonpayahay-hafizNisarAhmedMarfani.mp3|118Sunnion_samane_rehmat-hafizNisarAhmedMarfani.mp3|119Tera_milad_main-hafizNisarAhmedMarfani.mp3|120Wo_soay_lalazaar-hafizNisarAhmedMarfani.mp3|121Wobhi_din_aaiga-hafizNisarAhmedMarfani.mp3|122Yeikram_hay_mustafa-hafizNisarAhmedMarfani.mp3|123Yeikramhay-hafizNisarAhmedMarfani.mp3|124Yesab_tumhara_karam-hafizNisarAhmedMarfani.mp3|125AajSikmitraDi-khursheedAhmad.mp3|126AllahAllahAllahHu-khursheedAhmad.mp3|127BasaHuaHaiNabiKaDiyar-khursheedAhmad.mp3|128Bigri_hovi_banti_hay-khursheedAhmad.mp3|129Habibay_rabulula_mohammad-khursheedAhmad.mp3|130Ho_kay_ashkbar_sirf_aikbar-khursheedAhmad.mp3|131Jashne_amade_rasool-khursheedAhmad.mp3|132Jashn-e-aamad-e-rasool-khursheedAhmad.mp3|133Jitna_dia_sarkar_ne-khursheedAhmad.mp3|134Karam_ki_ik_nazar-khursheedAhmad.mp3|135Khuda_ka_zikar_kare-khursheedAhmad.mp3|136KiyaKhabarKiyaSaza-khursheedAhmad.mp3|137Koi_to_hay_jo_nizame_hasti-khursheedAhmad.mp3|138Loh_bhi_tu_qalam_bhi-khursheedAhmad.mp3|139Mangton_ko_sultan_banaya-khursheedAhmad.mp3|140MeinSoJaaoYaMustafaKehtayKehtay-khursheedAhmad.mp3|141Meray_dil_main_hay_yade_mohammad-khursheedAhmad.mp3|142Mery_arzo_mohammad-khursheedAhmad.mp3|143MujhKoBhiKash-khursheedAhmad.mp3|144Mujhay_dar_pe_phir_bulana-khursheedAhmad.mp3|145NabiKayIshqNay-khursheedAhmad.mp3|146SallayAllaPukaro-khursheedAhmad.mp3|147SallooAlaiheWaAlaihee-khursheedAhmad.mp3|148Sarkar_apna_roza_anwar-khursheedAhmad.mp3|149Shahe_madina-khursheedAhmad.mp3|150Shah-e-medina-khursheedAhmad.mp3|151ShanaBhalaKaunDasay-khursheedAhmad.mp3|152Sochta_hoo_main_wo_ghari-khursheedAhmad.mp3|153SozayDilChahayay-khursheedAhmad.mp3|154SubMilKarBoloSallayAla-khursheedAhmad.mp3|155TerayDarKaMeinGadaHoon-khursheedAhmad.mp3|156Tery_jalion_kay_neechay-khursheedAhmad.mp3|157Tu_amire_haram-khursheedAhmad.mp3|158YaSallayAllaMehboob-e-khuda-khursheedAhmad.mp3|159YaShah-e-umam-khursheedAhmad.mp3|160Ya_khuda_aik_din_jazbae_ashique-khursheedAhmad.mp3|161Ya_rahmattallilaalameen-khursheedAhmad.mp3|162Ya_shahe_umam-khursheedAhmad.mp3|163Ye_sab_tumhara_karam_hay-khursheedAhmad.mp3|164YehKaramHay-khursheedAhmad.mp3|166AagaeeMustafaKiSavari.mp3|167Aagaee_mustafa_ki_savari.mp3|168AaishafaeUmam.mp3|169Aakhan.mp3|170AamnaKaLaalAaGaya.mp3|171Aamnakalaalaaya.mp3|172AaqaAaqaBolBanday.mp3|173AbMereeNigahoonMainJajtaNaheenKoi.mp3|174AbdulRaufAsiyonKoDarTumhara.mp3|175AbdulRaufBariUmmidHai.mp3|176AbdulRaufBasApni.mp3|177AeDoDinDaMelaAeDoDinDeYari.mp3|178AeRasool-e-amin.mp3|179AjAyeNabiLajPal.mp3|180AjabRangPerHai.mp3|181Ajabrangparhaibaharemadinah.mp3|182AllahNabiDa.mp3|183AlvidaAlvidaHay.mp3|184ApanyDamanayKaram.mp3|185ApnayDaman-e-karamMeinChpaayeRakhna.mp3|186Aq-DaikhteKiyaHo.mp3|187Arsh-e-haqHaiMasnad-e-rifatRasoolullahKi.mp3|188ArzoSamanBaneHain.mp3|189AyeSabazGumbadWaley.mp3|190BaatJoKi.mp3|191BageJannat.mp3|192BaitTaiy.mp3|193Bakht-e-khustaNeMujhe.mp3|194BalagalulaBekamalehi.mp3|195BhikAta.mp3|196Bhini.mp3|197BullaloPhir.mp3|198ChalQalam.mp3|199Chalo.mp3|200ChamakTujhSePaatayHainSabPaanayWaalay.mp3|201ChamakTujhSePaatay.mp3|202Chamak.mp3|203DarPeBulao.mp3|204DareNabiPerYehUmar.mp3|205DilDerdSay.mp3|206DilMeraDunyaPeShedaHoGaya.mp3|207GabJumAakri.mp3|208GhousayAazam.mp3|209GunahoonKiAadat.mp3|210HabibEKhuda.mp3|211HaiKalamEIlahi.mp3|212HarDamHoMeraWird.mp3|213Hazir.mp3|214HumPerNazar.mp3|215Huzor.mp3|216IshqK.mp3|217JadalHussani.mp3|218JaisayMeray.mp3|219Jj-MuhammadKaRoza.mp3|220JunaidJamshedMubarakTujhayAeArzayMadina.mp3|221KabGunahonSay.mp3|222KabbayK.mp3|223KabhiMujhParBhiHoRehmat.mp3|224KhilaMeray.mp3|225Khuda.mp3|226KuchAisaKarDay.mp3|227Lagatay.mp3|228Maang.mp3|229MadaniMadineWale.mp3|230MadinaYaad.mp3|231MadineDiyanPakGaliyan.mp3|232MadniMadeneWale.mp3|233MahfilENaat.mp3|234MainJo.mp3|235MainMadeneChala.mp3|236MainMangtaHoon.mp3|237MainNazrKaroon.mp3|238MakkiMadani.mp3|239ManqabatEGhous.mp3|240MeethaMeetha.mp3|241MenoonAapSaharaDe.mp3|242MeraDilTarapRahaHay.mp3|243MereyAaqa.mp3|244MeriBaatBanGayeeHae.mp3|245MeriDharkan.mp3|246MeriKismat.mp3|247Mujda.mp3|248MujeBiMadineBulaMereMola.mp3|249NaArshEAman.mp3|250NaKabay.mp3|251Naat-Allahexcellent.mp3|252Naat-LabPeAatiHaiDua.mp3|253NaatInGojra.mp3|254Naat_aj_aye_nabi_laj.mp3|255Naat_dar_pe_bulao_w.mp3|256Naat_kabhi_mujh_par_.mp3|257Naat_madine_diyan_pa.mp3|258Naat_main_mangta_hoo.mp3|259Naat_menoon_aap_saha.mp3|260Naat_meri_baat_ban_g.mp3|261Naat_sarian_thoo_uch.mp3|262Naat_sarkar_ko_ro_ro.mp3|263Naat_ya_rasool_allah.mp3|264NaatsParteRahoNamaz.mp3|265Nakahin.mp3|266PhirMadineKa.mp3|267RahayJatay.mp3|268RookLaytiHai.mp3|269SaharaChahiya.mp3|270SanooApnayKaolBulaLay.mp3|271SarianThooUchiTeriShan.mp3|272SarkarKoRoRoKar.mp3|273SarkarYehNaamTumhara.mp3|274SerwarEAmbiya.mp3|275Shahe.mp3|276SochTa.mp3|277SubSay.mp3|278SubhaTaibaMeinHoi.mp3|279Subha.mp3|280SunloAayPeeronKayPeer.mp3|281Syednekarbalamain.mp3|282Tag.mp3|283Taskeen.mp3|284Tera.mp3|285ToKuch.mp3|286TumBhi.mp3|287Unkeemehak.mp3|288UnkiMehak.mp3|289Wah.mp3|290WohSarwer.mp3|291WohSoa.mp3|292YaRabHai.mp3|293YaRasoolAllahRahmatKiNazar.mp3|294Ya.mp3|295YehAarzoNahi.mp3|296YehKahtiThi.mp3|297Yehkehtithigharghar.mp3|298YusufIslamEtAl.mp3|299ZahayIsat.mp3|300ZairayKoayeJina.mp3|311Aamademustafahorahihai-mohammadFarhanQadri.mp3|312Aapjaanemustafahain-mohammadFarhanQadri.mp3|313Afsosbohatdoorhoongulzarenabisay-mohammadFarhanQadri.mp3|314Eidemeeladunnabihaidilbadamasroorhai-mohammadFarhanQadri.mp3|315Karamkaramkardaymeraymoula-mohammadFarhanQadri.mp3|316Khushiyanmanaodostomeeladkadinhai-mohammadFarhanQadri.mp3|317Labpaysalleala-mohammadFarhanQadri.mp3|318Madinaykaywaalidoaalamkaydaata-mohammadFarhanQadri.mp3|319Meinlajpaalatay-mohammadFarhanQadri.mp3|320Mustafajaanerehmatkameeladhai-mohammadFarhanQadri.mp3|321Asma_ul_husna-imranSheikhAttari.mp3|322Bari_umeed_hay_sarkar-imranSheikhAttari.mp3|323Dil_main_hay_arzoo-imranSheikhAttari.mp3|324EidonKiEid-imranSheikhAttari.mp3|325Kionkar_naho_makkah_se-imranSheikhAttari.mp3|326Kitthay_meher_ali-imranSheikhAttari.mp3|327Kon_kehta_hay_ankhain-imranSheikhAttari.mp3|328Meray_janib_bhi_ho-imranSheikhAttari.mp3|329Na_hoa_aram_jis_beemar-imranSheikhAttari.mp3|330Rehmatalilalamin-imranSheikhAttari.mp3|331Assalamoalaiykum-imranSheikhAttari.mp3|332Falaksaychaandutra-imranSheikhAttari.mp3|333Hasbirabijalallah-imranSheikhAttari.mp3|334Labaiykallahumalabaiyk-imranSheikhAttari.mp3|335Madinahmadinah-imranSheikhAttari.mp3|336Mohammadisthesymbolofallah-imranSheikhAttari.mp3|337Mohammadsyedekonain-imranSheikhAttari.mp3|338Mysorrowsare-imranSheikhAttari.mp3|339Sweetmadinahsweetmadinah-imranSheikhAttari.mp3|340Tahanabina-imranSheikhAttari.mp3|341Aayenabipeyaraynabi-imranSheikhAttari.mp3|342Assimalangaanpeerday-imranSheikhAttari.mp3|343Bolosallealaihewaaalehe-imranSheikhAttari.mp3|344Madinaywalayaminadalaal-imranSheikhAttari.mp3|345Nahoaraamjisbemarko-imranSheikhAttari.mp3|346Peyarapeyarahaymadinah-imranSheikhAttari.mp3|347Pukaroyarasoolallah-imranSheikhAttari.mp3|348Taranaymustafakayjhomkar-imranSheikhAttari.mp3|349AppSaDonoJahaMen-imranSheikhAttari.mp3|350DuniaKaSubSayBaraJashn-imranSheikhAttari.mp3|351FatimaKaChandHainHussain-imranSheikhAttari.mp3|352HamenMustafaSayPiarHai-imranSheikhAttari.mp3|353LagaoGhosKaNara-imranSheikhAttari.mp3|354MatwarayTorayNaamKay-imranSheikhAttari.mp3|355MeraNabiHaiMeraEman-imranSheikhAttari.mp3|356MoraKhwajaMoinuddin-imranSheikhAttari.mp3|357NabiPayApnayDuroodBhayjo-imranSheikhAttari.mp3|358QatraMangayJoKoi-imranSheikhAttari.mp3|359WahWahSall-e-ala-imranSheikhAttari.mp3|360AllahHooAllahHoo-fuzailRazaQadri.mp3|361HuzurAisaKoiIntizamHojaey-fuzailRazaQadri.mp3|362MainSojaoonYaMustafaKahtayKahtay-fuzailRazaQadri.mp3|363MeraTuSabKuchAapPerKurban-fuzailRazaQadri.mp3|364MeranWalyonKayImam-fuzailRazaQadri.mp3|365QaseedaBurdaSharif-fuzailRazaQadri.mp3|366SalamTajdarEHram-fuzailRazaQadri.mp3|367AhlaonWaSahlaonYaRasoolAllahSaw-fuzailRazaQadri.mp3|368AllahKaramAllahKaram-fuzailRazaQadri.mp3|369DurooodEPak-fuzailRazaQadri.mp3|370MainTuKhudOnKDarKa-fuzailRazaQadri.mp3|371RokLetiHaiApkiNisbat-fuzailRazaQadri.mp3|372YaElaahiYaElaahi-fuzailRazaQadri.mp3|373HamMustafaeeHain-fuzailRazaQadri.mp3|374HarMushkilKardayAsan-fuzailRazaQadri.mp3|375KhilaMerayDilKiKaliGhousEAzam-fuzailRazaQadri.mp3|376MohobatMainApniGhumaYaElahi-fuzailRazaQadri.mp3|377SarkarTawajjaFarmaeye-fuzailRazaQadri.mp3|378SuntayHainKayMahsharMain-fuzailRazaQadri.mp3|379YaRasoolAllahTereyDarKiFazaonKoSalam-fuzailRazaQadri.mp3|380Aey_saba_le_ja_madinay-muhammadMushtaqQadri.mp3|381Aey_shafae-muhammadMushtaqQadri.mp3|382Agai_mustafa_marhaba-muhammadMushtaqQadri.mp3|383Amna_ka_lal_aya-muhammadMushtaqQadri.mp3|384Ao_milkar_jashne_wiladat_manai-muhammadMushtaqQadri.mp3|385Arshey_haq_hey-muhammadMushtaqQadri.mp3|386Aysaba-muhammadMushtaqQadri.mp3|387Ayshehenshahmadina-muhammadMushtaqQadri.mp3|388Bara_rabiul_awal_kay-muhammadMushtaqQadri.mp3|389Bhardo_jhoali-muhammadMushtaqQadri.mp3|390Bhini_suhani_subhmein-muhammadMushtaqQadri.mp3|391Chalo_diyare_nabi_ki_janib-muhammadMushtaqQadri.mp3|392ChamakTujhSayPatayHain-muhammadMushtaqQadri.mp3|393Chamak_tujh_se_paatey-hey-muhammadMushtaqQadri.mp3|394Dil_ko_unse_khuda-muhammadMushtaqQadri.mp3|395Do_sadqa_deedar-muhammadMushtaqQadri.mp3|396Fajr_ka_waqt-muhammadMushtaqQadri.mp3|397Ham_faqeeron_ko_madinay-muhammadMushtaqQadri.mp3|398Hamko_apni_talab_se-muhammadMushtaqQadri.mp3|399Haqiqatmain-muhammadMushtaqQadri.mp3|400Hey_kalaame_ilaahi_mein-muhammadMushtaqQadri.mp3|401Imanhay-muhammadMushtaqQadri.mp3|402Kaba_key_badruduja-muhammadMushtaqQadri.mp3|403Kayibratkijaahay-muhammadMushtaqQadri.mp3|404Kharab_haal_kiya-muhammadMushtaqQadri.mp3|405Kya_mehektey_hey-muhammadMushtaqQadri.mp3|406La_ilaha_ilallah-muhammadMushtaqQadri.mp3|407Lam_yati_naziro-muhammadMushtaqQadri.mp3|408Madinay_kay_zaair_salam-muhammadMushtaqQadri.mp3|409Madinay_ki_taraf_phir-muhammadMushtaqQadri.mp3|410Madnaynoonjanwalay-muhammadMushtaqQadri.mp3|411Mehboobe_kibriya_se_mera_salam-muhammadMushtaqQadri.mp3|412Mehboobkimehfilko-muhammadMushtaqQadri.mp3|413Meray_sarkar_agai-muhammadMushtaqQadri.mp3|414Mujhkotaibamainbulalo-muhammadMushtaqQadri.mp3|415Mustafa_jaaney_rahmat-muhammadMushtaqQadri.mp3|416Naimatainbanta-muhammadMushtaqQadri.mp3|417Nichy_ankhoun_ki_sharmo_haya-muhammadMushtaqQadri.mp3|418Nigahe_karam_ho-muhammadMushtaqQadri.mp3|419Noorimehfil-muhammadMushtaqQadri.mp3|420Paishhaqmuszda-muhammadMushtaqQadri.mp3|421Phiruthawalwa-muhammadMushtaqQadri.mp3|422Qasida_1-muhammadMushtaqQadri.mp3|423Qasida_2-muhammadMushtaqQadri.mp3|424Qasida_ghosia-muhammadMushtaqQadri.mp3|425Qasida-e-miraj-muhammadMushtaqQadri.mp3|426Rahmatallilaalameen-muhammadMushtaqQadri.mp3|427Sabseola-muhammadMushtaqQadri.mp3|428Sairaygulshan-muhammadMushtaqQadri.mp3|429Salam-muhammadMushtaqQadri.mp3|430Serverkahoon-muhammadMushtaqQadri.mp3|431Subah_taiba_main_hoi-muhammadMushtaqQadri.mp3|432Unkay_anay_ki_khushi_hay-muhammadMushtaqQadri.mp3|433Unkimehakne-muhammadMushtaqQadri.mp3|434Uthay_hath_behere_dua-muhammadMushtaqQadri.mp3|435Wahkiajoodokaram-muhammadMushtaqQadri.mp3|436Wokamalhusn-muhammadMushtaqQadri.mp3|437Ya_elahi-muhammadMushtaqQadri.mp3|438Ya_mustafa_ata_ho-muhammadMushtaqQadri.mp3|439Ya_nabi_salamun-muhammadMushtaqQadri.mp3|440Ya_rasoolalah_salam_alaika-muhammadMushtaqQadri.mp3|441Ya_shafi-muhammadMushtaqQadri.mp3|442Arshehaqhay-muhammadZubairMecci.mp3|443Asionkodartumharamilgaya-muhammadZubairMecci.mp3|444Aysabamustafa-muhammadZubairMecci.mp3|445Ayshafimmsha-muhammadZubairMecci.mp3|446Bharamjiska-muhammadZubairMecci.mp3|447Chamaktujhsepatayhian-muhammadZubairMecci.mp3|448Farsikalam-muhammadZubairMecci.mp3|449Habbekhudaka-muhammadZubairMecci.mp3|450Ham_khak_hain-muhammadZubairMecci.mp3|451Hamkhakhain-muhammadZubairMecci.mp3|452Kabhiusshakskayaibon-muhammadZubairMecci.mp3|453Karamjoapka-muhammadZubairMecci.mp3|454Khilameraydilkikali-muhammadZubairMecci.mp3|455Kuchaisakardemeray-muhammadZubairMecci.mp3|456Labpenaat-muhammadZubairMecci.mp3|457Lahadmainishq-muhammadZubairMecci.mp3|458Madinaanaywalahay-muhammadZubairMecci.mp3|459Madinay_kay_wali-muhammadZubairMecci.mp3|460Mainmadinaychala-muhammadZubairMecci.mp3|461Mankabat-muhammadZubairMecci.mp3|462Mankabatgousalahazrat-muhammadZubairMecci.mp3|463Mankabatt-muhammadZubairMecci.mp3|464Munawar_mery_ankhon_ko-muhammadZubairMecci.mp3|465Munkabat-muhammadZubairMecci.mp3|466Mustafazaateyaktaaphain-muhammadZubairMecci.mp3|467Naraai_risalat_new-muhammadZubairMecci.mp3|468Nararisalat-muhammadZubairMecci.mp3|469Phirkay_gali_gali-muhammadZubairMecci.mp3|470Phirkaygaligalitaba-muhammadZubairMecci.mp3|471Qasidanoor-muhammadZubairMecci.mp3|472Qmairaj-muhammadZubairMecci.mp3|473Rangalamka-muhammadZubairMecci.mp3|474Salalahoalaikawasalam-muhammadZubairMecci.mp3|475Salam-muhammadZubairMecci.mp3|476Salamoalwida-muhammadZubairMecci.mp3|477Sartabaqadam-muhammadZubairMecci.mp3|478Sooayjanat-muhammadZubairMecci.mp3|479Surkhdinhayyameeraysama-muhammadZubairMecci.mp3|480Ya_allaho_ya_rehman-muhammadZubairMecci.mp3|481Zameenozaman-muhammadZubairMecci.mp3|499Arshe-e-haqMasnad-e-rifatRasoolallahKi.mp3|500MeinSadqayYaRasoolallah.mp3|501MeinSadqayYaRasoolallah.mp3|502MustafaNeSambalRakhaHai.mp3|503MustafaNeSambhaalRakhaHai.mp3|504MustafaNeSambhalRakhaHai-KhaakMujhMeinKamaalRakhaHai.mp3|505MustafaNeSambhalRakhaHai-KhaakMujhMeinKamalRakhaHai.mp3|506PurNoorHaiZamana.mp3|507RabbanaYaRabbana.mp3|508YaSyediIrhamlana.mp3|509YaSyediIrhamlana.mp3|510QaseedaBurdaShareef-a-qariKhushiMuhammad.mp3|511QaseedaBurdaShareef-b-qariKhushiMuhammad.mp3|512Aankhonkaywohpurkaif-qariShahidMehmood.mp3|513Jashnmanaoyaar-qariShahidMehmood.mp3|514Miladhummanayengay-qariShahidMehmood.mp3|515Peerandepeeryaro-qariShahidMehmood.mp3|516Pyaraynabitoupuchlo-qariShahidMehmood.mp3|517Sohndaduniyateaayayaro-qariShahidMehmood.mp3|518Sohriyankaramkamaday-qariShahidMehmood.mp3|519Tererauzaytouaavanmein-qariShahidMehmood.mp3|520Yanabisallealapyaraynabi-qariShahidMehmood.mp3|521AagaeyAagaeyAaqas.a.w.w-qariShahidMehmood.mp3|522AllahAllahAllahKar-qariShahidMehmood.mp3|523AllahHuAllah-qariShahidMehmood.mp3|524KaramKamayaSaiyan-qariShahidMehmood.mp3|525MaawanNe-qariShahidMehmood.mp3|526MeraMurshidSohnran-qariShahidMehmood.mp3|527SohnaAagaya-qariShahidMehmood.mp3|528ZindaHainZinda-qariShahidMehmood.mp3|529Qasida-e-burdaShareefcomplete.mp3|530Agar_koi_apna_bhala-saeedHashmi.mp3|531Lam_yati_nazeero-saeedHashmi.mp3|532MustafaJan-e-rehmatPayLakhonSalam.mp3|533Aaiyanthandihawawanmadinaydiyan-shahbazQamarFareedi.mp3|534Aayakamliwala-shahbazQamarFareedi.mp3|535Bigdibanaomakkimadani-shahbazQamarFareedi.mp3|536Harkoochayharnagaraliali-shahbazQamarFareedi.mp3|537Humaywohapnakehtayhain-shahbazQamarFareedi.mp3|538Meinkoyalmerabaagmadinah-shahbazQamarFareedi.mp3|539Meribaatbangayeehaiteribaat-shahbazQamarFareedi.mp3|540Saanuapnaykolbulalay-shahbazQamarFareedi.mp3|541Sachibaatseekhatayyehhain-shahbazQamarFareedi.mp3|542Shah-e-madinahitrosaybadhkarterapaseena-shahbazQamarFareedi.mp3|543Wohkaisasamahogawohkaisighadihogee-shahbazQamarFareedi.mp3|544Zikr-e-khair-ul-warabeykhatarkeejeye-shahbazQamarFareedi.mp3|545Ah_reh_jati_hay_falak_per-siddiqIsmail.mp3|546Dasan_galki_khazeene_di-siddiqIsmail.mp3|547Habibe_khuda_ka-siddiqIsmail.mp3|548Kion_na_ho_har_lamha-siddiqIsmail.mp3|549Madinay_ka_safar_hay-siddiqIsmail.mp3|550Mangton_ko_sultan_banaya-siddiqIsmail.mp3|551Mat_poochiye_kay_kiya_hay-siddiqIsmail.mp3|552Meray_dil_main_ishqehabib-siddiqIsmail.mp3|553Mujhko_taiba_main_bulalo-siddiqIsmail.mp3|554Noori_mehfil-siddiqIsmail.mp3|555Sarwar_kahoon_kay_malik-siddiqIsmail.mp3|556Unkay_gham_se_choor-siddiqIsmail.mp3|557Yarasoolalah_teray_darki-siddiqIsmail.mp3|558Ye_naatemustafa_ka-siddiqIsmail.mp3|559Breathless-syedFurqanQadri.mp3|560HumKaakhHain-syedFurqanQadri.mp3|561MiltaHaiKiyaMadinayMein-syedFurqanQadri.mp3|562Aaosarkarmeray-syedFurqanQadri.mp3|563Aaqadiyamehfilansajawand-syedFurqanQadri.mp3|564Aminakalaal-syedFurqanQadri.mp3|565Bahredeedarhaimushtaqharnazar-syedFurqanQadri.mp3|566Meinbehaksakoonyehmajaalkiya-syedFurqanQadri.mp3|567Meramadnisohndaaagaya-syedFurqanQadri.mp3|568Nabiyadasardar-syedFurqanQadri.mp3|569Sarkarkasadqahbattahai-syedFurqanQadri.mp3|570Yarabbedojahan-syedFurqanQadri.mp3|571Balagalula_bekamalehi-rehanQadri.mp3|572Har_dam_ho_mera_wird-rehanQadri.mp3|573Hay_shahed_se_bhi_meetha-rehanQadri.mp3|574Jitna_meray_khuda_ko_hay-rehanQadri.mp3|575Sab_se_olahoala_hamara_nabi-rehanQadri.mp3|576Sarkar_ye_naam_tumhara-rehanQadri.mp3|577Wohi_rab_hay_jis_ne_tujhko-rehanQadri.mp3|578Ya_khuda_jism_main_mery-rehanQadri.mp3|579Ya_nabi_salamun_alaika-rehanQadri.mp3|580Ye_sab_tumhara_karam_hay-rehanQadri.mp3|581Zameen_o_zaman-rehanQadri.mp3|582Aatayhaindekhowaalieummat-syedRehanAttari.mp3|583Bhardojholimerijaaneaalam-syedRehanAttari.mp3|584Bolimurshidwalibol-syedRehanAttari.mp3|585Humkhaakhainaurkhaanhimaavahaihumara-syedRehanAttari.mp3|586Khushiyonkatehwaraaya-syedRehanAttari.mp3|587Mittayhainjahanbharkay-syedRehanAttari.mp3|588Nabikayjaisakoinaheenhai-syedRehanAttari.mp3|589Terayishqdeedolatmiljaaye-syedRehanAttari.mp3|590WohjochahainchandKotodddain-syedRehanAttari.mp3|591Hoshokhiradsaykaamliyahai-syedSabeehuddinRehmani.mp3|592Jispaasayveetoorjaanwa-syedSabeehuddinRehmani.mp3|593Jolamhaythaysukoonkay-syedSabeehuddinRehmani.mp3|594Khuwabtoraydekhathoon-syedSabeehuddinRehmani.mp3|595Kubchudayanaheenhumkoghumsay-syedSabeehuddinRehmani.mp3|596Lokhatamhuataibakasafar-syedSabeehuddinRehmani.mp3|597Qaseedaburdahshareef-syedSabeehuddinRehmani.mp3|598Thehrihooyeeaankhonmein-syedSabeehuddinRehmani.mp3|608AaDilMeinTujeRakhlou-yousufMemon.mp3|609AajJashneCharagah-yousufMemon.mp3|610BaraRabiulAwal-yousufMemon.mp3|611ChaGayeAbreKaram-yousufMemon.mp3|612Chehrakamliwalayka-yousufMemon.mp3|613ChourFikarDuniyaKi-yousufMemon.mp3|614Ekbaarbulamaulasarkardayboohetay-yousufMemon.mp3|615Hamdkaywastay-yousufMemon.mp3|616HarSooHeIzharMadineWaleKa-yousufMemon.mp3|617Jowastanabikadeykarsadanadega-yousufMemon.mp3|618Kinnisohndisuratsohnaydee-yousufMemon.mp3|619Laillaha-illalha-yousufMemon.mp3|620Maareaangardiyegujratinaat-yousufMemon.mp3|621Merajwalayaaqadilmein-yousufMemon.mp3|622Meraysarkaraaye-yousufMemon.mp3|623MereLabPeNaam-e-muhammad-yousufMemon.mp3|624MursheedDaDidaar-yousufMemon.mp3|625NabiMeraNabiMera-yousufMemon.mp3|626Poochojibrailsaysarkarkokaisapaya-yousufMemon.mp3|627Qtv-bahar-e-naatYousufMemon-yousufMemon.mp3|628SadqaLeyneNoorKa-yousufMemon.mp3|629SonneYaNaLoSonna-yousufMemon.mp3|630ZikrENabiLajpal-qariShahidMehmood.mp3|631MeinHoonSarkarEMadinaKaGada-qariShahidMehmood.mp3|632NabiYaNabi-qariShahidMehmood.mp3|633JashanEMilaadMubarak-qariShahidMehmood.mp3|634MaaDiShaan-qariShahidMehmood.mp3|635AayeMereSarkar-qariShahidMehmood.mp3|636MeriJholiMeinRehteHain-qariShahidMehmood.mp3|637DewaneJoBhiMangdeNay-qariShahidMehmood.mp3|638IshqNabiDa-qariShahidMehmood.mp3|30101Track1.mp3|30202Track2.mp3|30303Track3.mp3|30404Track4.mp3|30505Track5.mp3|30606Track6.mp3|30707Track7.mp3|30808Track8.mp3|30909Track9.mp3|31010Track10.mp3|49767.mp3|49868.mp3|59911.Track11s.mp3|60012.Track12s.mp3|60113.Track13s.mp3|60214.Track14s.mp3|60315.Track15s.mp3|60416.Track16s.mp3|60517.Track17s.mp3|60618.Track18s.mp3|60719.Track19s.mp3|482136.mp3|483150.mp3|484169.mp3|485171.mp3|486172.mp3|487175.mp3|488178.mp3|489181.mp3|490182.mp3|491188.mp3|492229.mp3|493233.mp3|494234.mp3|495236.mp3|496238.mp3|1650303Selawat.mp3"},
{n="Naatein - Hafiz Tahir Qadri (141 Naats)", l="Urdu", i="NaatsOfRasool-Ul-ALLAHHafizTahirQadriAlbums", s="bk_naats_tahir141", c="naat", d="001AaoPadheinQuran-hafizTahirQadri.mp3|002AaoSabNabiNabiKarein-hafizTahirQadri.mp3|003AapHainEiman-e-jaan-hafizTahirQadri.mp3|004AllahHummaSalleAlaa-hafizTahirQadri.mp3|005BadeSakhiHainMadineWale-hafizTahirQadri.mp3|006ElhaiKoiAisaIntezaam-hafizTahirQadri.mp3|007ImdaadKoAao-hafizTahirQadri.mp3|008KaramKaramMaula-hafizTahirQadri.mp3|009Shehar-e-tamannaTabaMeinAaya-hafizTahirQadri.mp3|010AaqaKiAmadKeCharcheHain-hafizTahirQadri.mp3|011BulaloYaRasoolAllah-hafizTahirQadri.mp3|012DamDamAliAliDamDam-hafizTahirQadri.mp3|013KabaDikhaDeMaula-hafizTahirQadri.mp3|014MaulaShukarTera-hafizTahirQadri.mp3|015MereMuhammadAzeem-hafizTahirQadri.mp3|016MereSarkarKeGaiso-hafizTahirQadri.mp3|017SadaArbiDholanAaya-hafizTahirQadri.mp3|018YahNaraHamariJaan-hafizTahirQadri.mp3|019AllaHuPukarayJaa-hafizTahirQadri.mp3|020Arsh-e-haqHaiMasnad-e-riffatRasoolAllahKee-hafizTahirQadri.mp3|021MeinKinnooDassa-hafizTahirQadri.mp3|022SaharaChahyeSarkarZindagiKayLeye-hafizTahirQadri.mp3|023Tajdar-e-haramAeShehnshah-e-deen-hafizTahirQadri.mp3|024TuHiMaalik-e-behr-o-barHai-hafizTahirQadri.mp3|025ZikrchalouTaibahChaltayHain-hafizTahirQadri.mp3|026ZikrdhoomMachaadou-hafizTahirQadri.mp3|027ZikrislaamZindaahbad-hafizTahirQadri.mp3|028ZikrjitnaaDiyaaSarkaarNay-hafizTahirQadri.mp3|029ZikrkaramSarkaarKarrtayHain-hafizTahirQadri.mp3|030ZikrnabiKiNaatKiMahfil-hafizTahirQadri.mp3|031ZikrnahnuMuslimun-hafizTahirQadri.mp3|032ZikrpattaPattaBoottaBootta-hafizTahirQadri.mp3|033AllahBadshah-hafizTahirQadri.mp3|034AllahKaNoorAaya-hafizTahirQadri.mp3|035BaarweinKayDeewano-hafizTahirQadri.mp3|036ChangaNabiDa-hafizTahirQadri.mp3|037LagiyanNeMoja-hafizTahirQadri.mp3|038NabiKaOnchaNaam-hafizTahirQadri.mp3|039NadaronKoIlmKeMoti-hafizTahirQadri.mp3|040SunehriJaliyonWalay-hafizTahirQadri.mp3|041UnKiMehekNeDilKe-hafizTahirQadri.mp3|042DhoomMachadoAmadKiAagayeSarkaar-hafizTahirQadri.mp3|043HabibiYaMustafa-hafizTahirQadri.mp3|044KaabayKeeRonaqKaabayKaManzar-hafizTahirQadri.mp3|045KaramHoYaRasoolAllah-hafizTahirQadri.mp3|046MustafaKaWohNagarTeraBhyHay-hafizTahirQadri.mp3|047NoorWalaAayaHay-hafizTahirQadri.mp3|048RozayKiDewaarSayRishtaJorLiya-hafizTahirQadri.mp3|049SarMeraJhukaHayTereDarParMereAllah-hafizTahirQadri.mp3|050TerayIshqDeeDolatMilJaaye-hafizTahirQadri.mp3|051TereJiaMethaAaqa-hafizTahirQadri.mp3|052WohKamalHusn-e-huzoorHay-hafizTahirQadri.mp3|053BasMeraMaahiSallayAala-hafizTahirQadri.mp3|054FaaslonKoTakkalluf-hafizTahirQadri.mp3|055HumFaqeerLoog-hafizTahirQadri.mp3|056IslamZindabad-hafizTahirQadri.mp3|057KhushabDinHaram-e-pak-hafizTahirQadri.mp3|058MadinayKaSafarHai-hafizTahirQadri.mp3|059ParhtayRahoNamaz-hafizTahirQadri.mp3|060QasidaBurdaSharif-hafizTahirQadri.mp3|061TanamFarsoodaJaanPaara-hafizTahirQadri.mp3|062ZahayMuqqadarHuzoor-e-haq-hafizTahirQadri.mp3|063JeenaHuaDushwar-hafizTahirQadri.mp3|064JitnaDiyaSarkarNeMujhko-hafizTahirQadri.mp3|065KaramSarkarKarteHain-hafizTahirQadri.mp3|066LabbaikYaRasoolallah-hafizTahirQadri.mp3|067MuhammadNabina-hafizTahirQadri.mp3|068NehnuMuslimun-hafizTahirQadri.mp3|069TereBandeHainHum-hafizTahirQadri.mp3|070YaRasoolallahDaNara-hafizTahirQadri.mp3|071ZameenOZamanTumhareLiye-hafizTahirQadri.mp3|072AaqaAaqaBoleDil-hafizTahirQadri.mp3|073AliDaMalang-hafizTahirQadri.mp3|074ApniMakhlooq-hafizTahirQadri.mp3|075ChaloAajKhuwajaKa-hafizTahirQadri.mp3|076ChaloTaibaChalteHai-hafizTahirQadri.mp3|077HazooriKa-hafizTahirQadri.mp3|078JiyoSarkarKiKhatir-hafizTahirQadri.mp3|079MeraToSabKuchMeraNabiHai-hafizTahirQadri.mp3|080SartaBaKadamHai-hafizTahirQadri.mp3|081AllahHoKiZarbon-hafizTahirQadri.mp3|082ApneDarbarMeinAaye-hafizTahirQadri.mp3|083LamYatiNazeeruk-hafizTahirQadri.mp3|084MeraDilMadina-hafizTahirQadri.mp3|085MereAaqaDeteHain-hafizTahirQadri.mp3|086MiladKaMausamAaya-hafizTahirQadri.mp3|087PareParePe-hafizTahirQadri.mp3|088PyarHaiPyareNabi-hafizTahirQadri.mp3|089ShadmaniKaSama-hafizTahirQadri.mp3|090WhoIsTheLoveOne-hafizTahirQadri.mp3|091AllahHooPukarayJa-hafizTahirQadri.mp3|092AubMadinayBula-hafizTahirQadri.mp3|093ChamakTujhSeyPatayHain-hafizTahirQadri.mp3|094Ghos-e-aazamDastageer-hafizTahirQadri.mp3|095JubHusnThaUnKaJalwaNuma-hafizTahirQadri.mp3|096PhirMadinayKaMujhkoBulawaMila-hafizTahirQadri.mp3|097TarapMadineyKiHazriKeLiye-hafizTahirQadri.mp3|098BigdayHooyeBantayHainSubKaam-hafizTahirQadri.mp3|099BigdiBhiBanayenGayJalwayBhiDeekhayenGay-hafizTahirQadri.mp3|100KabayKayBadrooDujaTumPayKaradonDarood-hafizTahirQadri.mp3|101MuhammadKeDarPer-hafizTahirQadri.mp3|102NabiKiNaatKiMehfilSajanaHumNaChorenGay-hafizTahirQadri.mp3|103PattaPattaBootaBootaZikr-e-khudaMeinKhoya-hafizTahirQadri.mp3|104SarkarBulaayenQadmonMein-hafizTahirQadri.mp3|105SarwarKahoonKayMaalik-o-maulakahoonTujhay-hafizTahirQadri.mp3|106YaEelahiHarJagahTeriAtaKaSaathHo-hafizTahirQadri.mp3|107YaMohammadNoor-e-mujassam-hafizTahirQadri.mp3|108YaRasoolAllahKaram-hafizTahirQadri.mp3|109YaRubMadinayPaakMeinJaanaNaseebHo-hafizTahirQadri.mp3|110AtaiNaakaBilFaqr-hafizTahirQadri.mp3|111Lailahail-allah-hafizTahirQadri.mp3|112MarhabaYaMarhaba-hafizTahirQadri.mp3|113MureedanBaadir-hafizTahirQadri.mp3|114SalamSalamSalam-hafizTahirQadri.mp3|115SallaAlaihiMaulana-hafizTahirQadri.mp3|116SallaAlaik-hafizTahirQadri.mp3|117Sall-e-alaMohammadsaw-hafizTahirQadri.mp3|118Tala-al-badruAlaiyna-hafizTahirQadri.mp3|119YaKhaliq-al-aqwan-hafizTahirQadri.mp3|120YaRasoolAllah-hafizTahirQadri.mp3|121AllahAllahKareyeTaaGal-hafizTahirQadri.mp3|122AllahAllahNabiKaGharana-hafizTahirQadri.mp3|123HoKaramKaramKhudayaKaram-hafizTahirQadri.mp3|124KaabayKayBadru-doojaTumPayKaradonDurood-hafizTahirQadri.mp3|125MarhabaJaddalHussaniMarhaba-hafizTahirQadri.mp3|126MeeranWaliyonKayImam-hafizTahirQadri.mp3|127SayyediYaHabibiMaulai-hafizTahirQadri.mp3|128YaEelahiHarJagahTeriAtaKaSaathHo-hafizTahirQadri.mp3|129YaRasoolAllahKaram-hafizTahirQadri.mp3|130YaRasoolAllahTeriAamadKaJashan-hafizTahirQadri.mp3|131AliHaiderKaGharana-hafizTahirQadri.mp3|132BapaKaSikka-hafizTahirQadri.mp3|133BohotDinHogayayTaiba-hafizTahirQadri.mp3|134ChaloDardBantain-hafizTahirQadri.mp3|135ChaloNamazParhain-hafizTahirQadri.mp3|136JananayMaMuhammad-hafizTahirQadri.mp3|137KaramHaiKaramHai-hafizTahirQadri.mp3|138MerayMuhammadBanayHainDulha-hafizTahirQadri.mp3|139TuHiGhaffarHai-hafizTahirQadri.mp3|140YaShahrayRamadan-hafizTahirQadri.mp3|141YahanBapaKaSikka-hafizTahirQadri.mp3"},
{n="Naatein - Anas Yunus (45 Naats)", l="Urdu", i="AhnafMedia-Audios-Naat-Anas-Yunus", s="bk_naats_anas45", c="naat", d="AapKiNaatain.mp3|AbYehKehtaHoonKMadine.mp3|AeMeriQoumKAhleZarDosto.mp3|AeyMerayMaalik.mp3|Afzalhay.mp3|AllahAllah.mp3|AllahAllahJaaneJaana.mp3|AllahBohatBaraHay.mp3|AmmiAisha.mp3|DarbarPeHazirHye.mp3|EveryNightAndEveryDay.mp3|GilaafeKaaba.mp3|HaramKiMuqaddasHawaonMain.mp3|HaramSeRishta.mp3|Hudoodullah.mp3|KabhiUsShakhs.mp3|Kalam-e-Jami.mp3|MarhabaKitnaHaseenMeraNabis.a.w.mp3|MeraEhsaas.mp3|MeraPayamberAzimTarHay.mp3|MerayPaisheNazar.mp3|MujhayFurqatMain.mp3|Mundarjaat.mp3|NabiKeSahaba.mp3|Nadaan.mp3|PiyraPiyarUsiKaaHayNaam.mp3|QaseedahHassaan.mp3|QasidaHuzn.mp3|QasidaHuznHassanBinSabit.mp3|Rabbana.mp3|RamzaanKiRehmaten.mp3|Rukh-e-Mustafa.mp3|SahilSayLagayGaKhabheMeraBiSafina.mp3|SazaDenayWale.mp3|ShaaneAmmiAyesharaziallahuTaalaAnha.mp3|SiraikiNaat.mp3|SubhaanallahSubhaanallah.mp3|SunoDastan-e-muztar.mp3|TerePaakNaam.mp3|TeriSuratPeHoQurban.mp3|WaqiaTaef.mp3|ZulfeNabiSalalahuAlayhiWasalam.mp3|aaj-kay-nojwaan.mp3|hamoon-wa-ghamoon.mp3|hateemo.mp3"},
{n="Pashto Naatein - Asmatullah Jarar (Darna Zaar Sham, 11)", l="Pashto", i="darna-zaar-sham-PIGHAMBARA-2016", s="bk_naats_jarar11", c="naat", d="DaInsOJinMakhluqatoonoKhdaya.mp3|DarnaZarShamPighambaraPaMongGrana.mp3|FaneDunyaDaByaOkryArmanoona.mp3|KhaarMadeenaZamaDaYarMadeena.mp3|KhkulyMohammadNabi.mp3|NaseemaPasaPaHavaSha.mp3|PaMungGranYeZamongKhogNabiSardara.mp3|QurbanQurbanNabiDaZraDarmanNabi.mp3|StaDaDeedanPaTamaShpySabaKaooma.mp3|TaOdravaleDBystanoAsmanoona.mp3|ZaMadeenyMunavaryLaZama.mp3"},
{n="Pashto Naatein - Asmatullah Jarar (Zargea Sha Qarar, 10)", l="Pashto", i="Zargea-Sha-Qarar-Album-27", s="bk_naats_jarar27", c="naat", d="BilalTaKriPygham.mp3|GhvaramMafiZaToobaGarYm.mp3|HaalDaUmmatOgora.mp3|JaroKramStaWatan.mp3|KhkulyDyDyrKhkulyDy.mp3|PaArshKCharchaDaZamaDaJananMeny.mp3|TaaGhvariBsTaaGhvari.mp3|VBaSakhtaWrazDaQyamat.mp3|VayaRataZarVayaJananMeSumraKhkulyDy.mp3|ZargeyaShaQararAwDasyNaChyShyPagal.mp3"},
{n="Pashto Naatein - Umar Hayat Durani (Album 19, 10)", l="Pashto", i="album-19-of-umar-hayat-durani", s="bk_naats_umar10", c="naat", d="HimatPakarDyBarakatPakyAllahAchave.mp3|KalyDaJananLakaChyMaNaPatyKege.mp3|KhvandDaMuhabatMeZargeeWaghasto.mp3|MadeenaKhaarDaNazavaloKhaar.mp3|MenyDyMalangGhundySyzalyYam.mp3|PaSheenGumbadStargyYakhoomByaPataNaLage.mp3|RubaemadeenyStaAshiqanRabandyGranD.mp3|ShukarChyMelmeDaYaarPaDarDyKram.mp3|ZaDaHaghaChaGhulamYamChyGhulamMeDaAqaDy.mp3|ZamaDaJvandKhkulaWaZamaSaaWaZamaMoor.mp3"},
{n="Urdu Hamd o Tarana - Hamad Bari (12)", l="Urdu", i="hamad-bari", s="bk_naats_hamad12", c="naat", d="Dar Mola Peh Sawali Ko.mp3|Dil Ko Agar Chamkana.mp3|HAMD IN URDU VERY BEAUTYFUL URDU NASHEED HAMAD SWEET.mp3|Hamin dar peh.mp3|Har Dam Allah Allah Kar.mp3|Ho Karam Mujh Peh.mp3|Kaaba ka Safar Kaisa Lagay ga. by Naeem ur Rehman.MP3|Main Hoon Banda Tera.mp3|Shukar Hai Tera Khudaya.mp3|Soraj Meen Chamk Teri.mp3|tera khawan.mp3|us rab do alam ki ata.mp3"},
{n="Naatein - Aey Mere Moula (3)", l="Urdu", i="AeyMereMoula", s="bk_naats_moula3", c="naat", d="AeyMereMoula.mp3|AeyMereMoula_64kb.mp3|AeyMereMoula_vbr.mp3"},
}
function V25.urlDec(t)
return (string.gsub(tostring(t or ""), "%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end
function V25.cleanName(f)
local t = V25.urlDec(f)
t = string.gsub(t, "%.mp3$", "")
t = string.gsub(t, "[_%-]", " ")
t = string.gsub(t, "%s+", " ")
t = string.gsub(t, "^%s+", "")
t = string.gsub(t, "%s+$", "")
return t
end
function V25.gregToJD(y, m, d)
if m < 3 then y = y - 1 m = m + 12 end
local a = math.floor(y / 100)
local b = 2 - a + math.floor(a / 4)
return math.floor(365.25 * (y + 4716)) + math.floor(30.6001 * (m + 1)) + d + b - 1524
end
function V25.jdToHijri(jd)
local l = jd - 1948440 + 10632
local n = math.floor((l - 1) / 10631)
l = l - 10631 * n + 354
local j = math.floor((10985 - l) / 5316) * math.floor((50 * l) / 17719) + math.floor(l / 5670) * math.floor((43 * l) / 15238)
l = l - math.floor((30 - j) / 15) * math.floor((17719 * j) / 50) - math.floor(j / 16) * math.floor((15238 * j) / 43) + 29
local mo = math.floor((24 * l) / 709)
local dd = l - math.floor((709 * mo) / 24)
local yy = 30 * n + j - 30
return yy, mo, dd
end
function V25.gregToHijri(y, m, d)
return V25.jdToHijri(V25.gregToJD(y, m, d))
end
function V25.getIslamicDate()
local okH, aH, bH, cH, dH = pcall(function()
local y = tonumber(os.date("%Y")) or 2026
local m = tonumber(os.date("%m")) or 1
local d = tonumber(os.date("%d")) or 1
local off = tonumber(V25.getHijriOffset()) or 0
local hy, hm, hd = V25.jdToHijri(V25.gregToJD(y, m, d) + off)
local mU = V25.hijriMonthsUrdu[hm] or ("Month " .. tostring(hm))
local mE = V25.hijriMonthsEn[hm] or ("Month " .. tostring(hm))
return hd, mU, hy, mE
end)
if okH and aH then return aH, bH, cH, dH end
return nil, nil, nil, nil
end
function V25.islamicDateSimple()
local ok, hd, hm, hy, mUr, mEn = pcall(function()
local y = tonumber(os.date("%Y")) or 2026
local m = tonumber(os.date("%m")) or 1
local d = tonumber(os.date("%d")) or 1
local yy, mm = y, m
if mm < 3 then yy = yy - 1 mm = mm + 12 end
local a = math.floor(yy / 100)
local b = 2 - a + math.floor(a / 4)
local jd = math.floor(365.25 * (yy + 4716)) + math.floor(30.6001 * (mm + 1)) + d + b - 1524
jd = jd + (tonumber(V25.HIJRI_OFFSET_DAYS) or 0)
local l = jd - 1948440 + 10632
local n = math.floor((l - 1) / 10631)
l = l - 10631 * n + 354
local j = math.floor((10985 - l) / 5316) * math.floor((50 * l) / 17719) + math.floor(l / 5670) * math.floor((43 * l) / 15238)
l = l - math.floor((30 - j) / 15) * math.floor((17719 * j) / 50) - math.floor(j / 16) * math.floor((15238 * j) / 43) + 29
local hm2 = math.floor((24 * l) / 709)
local hd2 = l - math.floor((709 * hm2) / 24)
local hy2 = 30 * n + j - 30
local fnEn = {"Muharram","Safar","Rabi-ul-Awwal","Rabi-ul-Thani","Jumada-ul-Awwal","Jumada-ul-Thani","Rajab","Shaban","Ramadan","Shawwal","Dhul-Qadah","Dhul-Hijjah"}
local e1 = (V25.hijriMonthsEn and V25.hijriMonthsEn[hm2]) or fnEn[hm2] or ("Month " .. tostring(hm2))
local u1 = (V25.hijriMonthsUrdu and V25.hijriMonthsUrdu[hm2]) or ("\217\133\219\129\219\140\217\134\219\129 " .. tostring(hm2))
return hd2, hm2, hy2, u1, e1
end)
if ok and hd then return hd, hm, hy, mUr, mEn end
return nil
end
function V25.islamicLineRoman()
local hd, hm, hy, mUr, mEn = V25.islamicDateSimple()
if not hd then return "Islamic Calendar: " .. tostring(os.date("%d-%m-%Y")) end
return "Islamic Calendar: " .. tostring(hd) .. " " .. tostring(mEn) .. " " .. tostring(hy) .. " AH"
end
function V25.islamicLineUrdu()
local hd, hm, hy, mUr, mEn = V25.islamicDateSimple()
if not hd then return "\216\167\216\179\217\132\216\167\217\133\219\140 \216\170\216\167\216\177\219\140\216\174: " .. tostring(os.date("%d-%m-%Y")) end
return "\216\167\216\179\217\132\216\167\217\133\219\140 \216\170\216\167\216\177\219\140\216\174: " .. tostring(hd) .. " " .. tostring(mUr) .. " " .. tostring(hy) .. " \218\190"
end
function V25.islamicDateLine() return V25.islamicLineRoman() end
function V25.islamicDateLineUrdu() return V25.islamicLineUrdu() end
function V25.refreshIslamicDateViews()
pcall(function()
if screen ~= "home" then return end
local v1 = _G["txtIslamicDate"]
if v1 then v1.setText(V25.islamicDateLine()) end
local v2 = _G["txtIslamicDateUrdu"]
if v2 then v2.setText(V25.islamicDateLineUrdu()) end
end)
end
function V25.startDateTick()
local ok, err = pcall(function()
if V25.dateTick then handler.removeCallbacks(V25.dateTick) end
V25.dateTick = Runnable({run = function()
pcall(function() V25.refreshIslamicDateViews() end)
pcall(function() handler.postDelayed(V25.dateTick, 60000) end)
end})
handler.postDelayed(V25.dateTick, 60000)
pcall(function() V25.refreshIslamicDateViews() end)
end)
if not ok then showErrorDialog("Islamic calendar tick error", err) end
end
local function calcTahajjud(maghrib, fajr)
local mh, mm = maghrib:match("(%d+):(%d+)")
local fh, fm = fajr:match("(%d+):(%d+)")
if not mh or not fh then return "--:--" end
local m_mins = tonumber(mh)*60 + tonumber(mm)
local f_mins = tonumber(fh)*60 + tonumber(fm) + 1440
local diff = f_mins - m_mins
local lastThirdStart = m_mins + math.floor(diff * 2 / 3)
local h = math.floor(lastThirdStart / 60) % 24
local min = lastThirdStart % 60
return string.format("%02d:%02d to %02d:%02d", h, min, tonumber(fh)%24, tonumber(fm))
end
local lastPrayerFetchDate = prefs.getString("lastPrayerFetchDate", "")
M.todayDateString = function()
return os.date("%Y-%m-%d")
end
M.currentBatteryPercent = function()
local pct = -1
pcall(function()
local bm = activity.getSystemService(Context.BATTERY_SERVICE)
pct = bm.getIntProperty(4)
end)
return pct
end
M.fetchPrayerTimes = function(c, cntry, onDone)
Thread(Runnable{
run=function()
local function tryEndpoint(urlStr)
local ok, res = pcall(function()
local conn = URL(urlStr).openConnection()
conn.setConnectTimeout(10000) conn.setReadTimeout(15000)
local reader = BufferedReader(InputStreamReader(conn.getInputStream()))
local out = "" local line = reader.readLine()
while line do out = out..line line = reader.readLine() end
reader.close() return out
end)
if ok and res and res:find('"Fajr"') then return res end
return nil
end
local adj = 0
local adjQ = ""
local todayApiDate = os.date("%d-%m-%Y")
local byCity = "https://api.aladhan.com/v1/timingsByCity/"..todayApiDate.."?city="..URLEncoder.encode(c).."&country="..URLEncoder.encode(cntry).."&method=1"..adjQ
local byAddress = "https://api.aladhan.com/v1/timingsByAddress/"..todayApiDate.."?address="..URLEncoder.encode(c..", "..cntry).."&method=1"..adjQ
local result = tryEndpoint(byCity)
if not result then result = tryEndpoint(byAddress) end
local success = (result ~= nil)
activity.runOnUiThread(Runnable{
run=function()
local ok = false
if success and result then
local f = result:match('"Fajr":"(.-)"')
local d = result:match('"Dhuhr":"(.-)"')
local a = result:match('"Asr":"(.-)"')
local m = result:match('"Maghrib":"(.-)"')
local i = result:match('"Isha":"(.-)"')
local sr = result:match('"Sunrise":"(.-)"')
local tzName = result:match('"timezone":"(.-)"') or savedPrayerTimezone
if f then
savedCity = c savedCountry = cntry
savedPrayerTimezone = tzName or savedPrayerTimezone
prayerFajr = f prayerDhuhr = d prayerAsr = a prayerMaghrib = m prayerIsha = i
if sr then prayerSunrise = sr end
lastPrayerFetchDate = M.todayDateString()
prefs.edit().putString("userCity", c).putString("userCountry", cntry).putString("pFajr", f).putString("pDhuhr", d).putString("pAsr", a).putString("pMaghrib", m).putString("pIsha", i).putString("pSunrise", prayerSunrise).putString("prayerTimeZone", savedPrayerTimezone).putString("lastPrayerFetchDate", lastPrayerFetchDate).apply()
pcall(function() scheduleCityAzans() end)
ok = true
end
end
if onDone then onDone(ok) end
end
})
end
}).start()
end
M.openLinkAndClose = function(urlStr)
pcall(function() activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(urlStr))) activity.finish() end)
end
local reciters = { {name="Qari Asad Attari (Dawat-e-Islami)", url="https://data2.dawateislami.net/download/tilawat-e-quran/ur/mp3/2018/", isDI=true}, {name="Mishary Rashid Alafasy", url="https://server8.mp3quran.net/afs/"}, {name="Abdul Basit", url="https://server6.mp3quran.net/basit/"}, {name="Saad Al-Ghamdi", url="https://server7.mp3quran.net/s_gmd/"}, {name="Maher Al Meaqli", url="https://server12.mp3quran.net/maher/"}, {name="Mahmoud Khalil Al-Hussary", url="https://server13.mp3quran.net/husr/"}, {name="Mohammed Siddiq Al-Minshawi", url="https://server10.mp3quran.net/minsh/"}, }
M.buildQuranUrl = function(reciterIdx, surahIdx)
local r = reciters[reciterIdx]
if r.isDI then
local diId = 59423 + surahIdx
return r.url .. diId .. ".mp3"
else
return r.url .. string.format("%03d", surahIdx) .. ".mp3"
end
end
M.findReciterIndexByName = function(name)
if not name or name == "" then return 1 end
for i, r in ipairs(reciters) do
if r.name == name then return i end
end
return 1
end
M.fetchRecitersFromAPI = function()
local ok, jsonStr = pcall(function()
local conn = URL("https://www.mp3quran.net/api/v3/reciters?language=eng").openConnection()
conn.setConnectTimeout(8000) conn.setReadTimeout(15000)
local reader = BufferedReader(InputStreamReader(conn.getInputStream()))
local res = "" local line = reader.readLine()
while line do res = res..line line = reader.readLine() end
reader.close() return res
end)
if not ok or not jsonStr then return nil end
local newList = {}
pcall(function()
local JSONObject = luajava.bindClass("org.json.JSONObject")
local root = JSONObject(jsonStr)
local arr = root.getJSONArray("reciters")
for i=0, arr.length()-1 do
local r = arr.getJSONObject(i)
local name = tostring(r.getString("name"))
local moshafArr = r.getJSONArray("moshaf")
local chosenServer = nil
for j=0, moshafArr.length()-1 do
local m = moshafArr.getJSONObject(j)
if m.getInt("surah_total")==114 then chosenServer = tostring(m.getString("server")) break end
end
if chosenServer then
table.insert(newList, {name=name, url=chosenServer})
if #newList >= 51 then break end
end
end
end)
if #newList == 0 then return nil end
return newList
end
M.saveRecitersCache = function(list)
local parts = {}
for _, r in ipairs(list) do
if not r.isDI then table.insert(parts, r.name.."|"..r.url) end
end
prefs.edit().putString("recitersCache", table.concat(parts, ";;")).apply()
end
M.loadRecitersCache = function()
local s = prefs.getString("recitersCache", "")
if s == "" then return nil end
local list = {}
for entry in string.gmatch(s, "([^;]+);;?") do
local n, u = entry:match("^(.-)|(.+)$")
if n and u then table.insert(list, {name=n, url=u}) end
end
if #list == 0 then return nil end
return list
end
local diReciterEntry = reciters[1]
local extraPinnedReciters = { {name="Saud Al-Shuraim", url="https://server7.mp3quran.net/shur/"}, {name="Abdul Rahman Al-Sudais", url="https://server11.mp3quran.net/sds/"}, {name="Syed Sadaqat Ali", url="https://archive.org/download/syed-sadaqat-ali/"}, }
M.withoutPinnedDuplicates = function(list)
local filtered = {}
for _, r in ipairs(list) do
local nameLower = tostring(r.name):lower()
local isDup = false
for _, p in ipairs(extraPinnedReciters) do
if nameLower:find(p.name:lower():match("[%w]+%s*[%w%-]*$") or p.name:lower(), 1, true) then isDup = true break end
end
if not isDup then table.insert(filtered, r) end
end
return filtered
end
local cachedList = M.loadRecitersCache()
if cachedList then
local merged = {diReciterEntry}
for _, p in ipairs(extraPinnedReciters) do table.insert(merged, p) end
for _, r in ipairs(M.withoutPinnedDuplicates(cachedList)) do table.insert(merged, r) end
reciters = merged
end
local savedReciterName = prefs.getString("lastReciterName", "")
currentReciter = M.findReciterIndexByName(savedReciterName)
local lastPlayedReciter = currentReciter
Thread(Runnable{run=function()
local liveList = M.fetchRecitersFromAPI()
if liveList then
local previouslySelectedName = reciters[currentReciter] and reciters[currentReciter].name or ""
local merged = {diReciterEntry}
for _, p in ipairs(extraPinnedReciters) do table.insert(merged, p) end
for _, r in ipairs(M.withoutPinnedDuplicates(liveList)) do table.insert(merged, r) end
handler.post(Runnable{run=function()
reciters = merged
M.saveRecitersCache(liveList)
currentReciter = M.findReciterIndexByName(previouslySelectedName)
end})
end
end}).start()
local surahNames = {"Al-Fatihah","Al-Baqarah","Al-Imran","An-Nisa","Al-Ma'idah","Al-An'am","Al-A'raf","Al-Anfal","At-Tawbah","Yunus","Hud","Yusuf","Ar-Ra'd","Ibrahim","Al-Hijr","An-Nahl","Al-Isra","Al-Kahf","Maryam","Ta-Ha","Al-Anbiya","Al-Hajj","Al-Mu'minun","An-Nur","Al-Furqan","Ash-Shu'ara","An-Naml","Al-Qasas","Al-Ankabut","Ar-Rum","Luqman","As-Sajdah","Al-Ahzab","Saba","Fatir","Ya-Sin","As-Saffat","Sad","Az-Zumar","Ghafir","Fussilat","Ash-Shura","Az-Zukhruf","Ad-Dukhan","Al-Jathiyah","Al-Ahqaf","Muhammad","Al-Fath","Al-Hujurat","Qaf","Adh-Dhariyat","At-Tur","An-Najm","Al-Qamar","Ar-Rahman","Al-Waqi'ah","Al-Hadid","Al-Mujadilah","Al-Hashr","Al-Mumtahanah","As-Saff","Al-Jumu'ah","Al-Munafiqun","At-Taghabun","At-Talaq","At-Tahrim","Al-Mulk","Al-Qalam","Al-Haqqah","Al-Ma'arij","Nuh","Al-Jinn","Al-Muzzammil","Al-Muddaththir","Al-Qiyamah","Al-Insan","Al-Mursalat","An-Naba","An-Nazi'at","Abasa","At-Takwir","Al-Infitar","Al-Mutaffifin","Al-Inshiqaq","Al-Buruj","At-Tariq","Al-A'la","Al-Ghashiyah","Al-Fajr","Al-Balad","Ash-Shams","Al-Layl","Ad-Duha","Ash-Sharh","At-Tin","Al-Alaq","Al-Qadr","Al-Bayyinah","Az-Zalzalah","Al-Adiyat","Al-Qari'ah","At-Takathur","Al-Asr","Al-Humazah","Al-Fil","Quraysh","Al-Ma'un","Al-Kawthar","Al-Kafirun","An-Nasr","Al-Masad","Al-Ikhlas","Al-Falaq","An-Nas"}
local paraSurahStart = {1,2,2,3,4,4,5,6,7,8,9,11,12,15,17,18,21,23,25,27,29,33,36,39,41,46,51,58,67,78}
local paraFirstAyah = {1,142,253,93,24,148,82,111,88,41,93,6,53,1,1,75,1,1,21,56,46,31,28,32,47,1,31,1,1,1}
local surahAyahCounts = {7,286,200,176,120,165,206,75,129,109,123,111,43,52,99,128,111,110,98,135,112,78,118,64,77,227,93,88,69,60,34,30,73,54,45,83,182,88,75,85,54,53,89,59,37,35,38,29,18,45,60,49,62,55,78,96,29,22,24,13,14,11,11,18,12,12,30,52,52,44,28,28,20,56,40,31,50,40,46,42,29,19,36,25,22,17,19,26,30,20,15,21,11,8,8,19,5,8,8,11,11,8,3,9,5,4,7,3,6,3,5,4,5,6}
local URLBASES = { urdu = "https://archive.org/download/complete-quran-with-urdu-translation-mishary-rashid-alafasy/", hindi = "https://archive.org/download/The_Noble_Quran_With_Hindi_Translation-Audio_MP3_HQ/", punjabi = "https://archive.org/download/AlQuranWithPunjabiTranslation/", english = "https://archive.org/download/quran-english-translation-audio/", sindhi = "https://archive.org/download/Al-quran-with-sindhi-translation------high-quality-audio-mp3/", hadith = "https://archive.org/download/sahih-bukhari-english-audio/", israrTafseer = "https://archive.org/download/tafseer-e-quran-urdu/", nawawi = "https://archive.org/download/40HadithNawawi/", }
local _lazyCache = {}
M.urduTranslationFiles = function()
if not _lazyCache.urdu then
_lazyCache.urdu = {
"001 Surah Fatiha.mp3", "002 Surah Al-Baqarah.mp3", "003 Surah Al-Imran.mp3", "004 Surah An-Nisa.mp3",
"005 Surah Maidah.mp3", "006 Surah Al Anam.mp3", "007 Surah Araf.mp3", "008 Surah Anfal.mp3",
"009 Surah Al Tauba.mp3", "010 Surah Yunus.mp3", "011 Surah Hud.mp3", "012 Suarh Yusuf.mp3",
"013 Surah Ar-Rad .mp3", "014 Surah Ibrahim.mp3", "015 Surah Hijr .mp3", "016 Surah Nahl.mp3",
"017 Surah Isra .mp3", "018 Surah Kahf .mp3", "019 Surah Maryam .mp3", "020 Surah Taha .mp3",
"021 Surah Al Anbiya .mp3", "022 Surah Hajj .mp3", "023 Surah Mumenoon.mp3", "024 Surah Noor .mp3",
"025 Surah Al-Furqan .mp3", "026 Surah Ash-Shuara .mp3", "027 Surah Naml .mp3", "028 Surah Qasas .mp3",
"029 Surah Ankaboot .mp3", "030 Surah Room .mp3", "031 Surah Luqman .mp3", "032 Surah Sajda .mp3",
"033 Surah Ahzab .mp3", "034 Surah Saba .mp3", "035 Surah Fatir .mp3", "036 Surah Yasin.mp3",
"037 Surah As-Saaffat .mp3", "038 Surah Sad .mp3", "039 Surah Az-Zumar .mp3", "040 Sarah Ghafir .mp3",
"041 Surah Fussilat .mp3", "042 Surah Ash-Shura .mp3", "043 Surah Zukhruf .mp3", "044 Surah Dukhan .mp3",
"045 Surah Al-Jathiya .mp3", "046 Surah Ahqaf .mp3", "047 Surah Muhammad .mp3", "048 Surah Fath .mp3",
"049 Surah Hujraat .mp3", "050 Surah Qaf .mp3", "051 Surah Adh-Dhariyat .mp3", "052 Surah At-Tur.mp3",
"053 Surah An-Najm.mp3", "054 Surah Al-Qamar.mp3", "055 Surah Rahman - wi.mp3", "056 Surah Al-Waqiah.mp3",
"057 Surah Al-Hadid.mp3", "058 Surah Al-Mujadilah.mp3", "059 Surah Al-Hashr.mp3", "060 Surah Al Mumtahana.mp3",
"061 Surah As-Saff.mp3", "062 Surah Al-Jumuah.mp3", "063 Surah Al-Munafiqun.mp3", "064 Surah At Taghabun - wi.mp3",
"065 Surah At Talaq.mp3", "066 Surah Tahreem.mp3", "067 Surah Mulk.mp3", "068 Surah Al-Qalam.mp3",
"069 Surah Al-Haqqah.mp3", "070 Surah Al Maarij.mp3", "071 Surah Nuh.mp3", "072 Surah Al-Jinn.mp3",
"073 Surah Muzzammil.mp3", "074 Surah Mudassir.mp3", "075 Surah Qiyamah.mp3", "076 Surah Insan.mp3",
"077 Surah Mursalat.mp3", "078 Surah An-Naba.mp3", "079 Surah An-Naziat -.mp3", "080 Surah Abasa.mp3",
"081 Surah At-Takwir.mp3", "082 Surah Al Infitar.mp3", "083 Surah Al-Mutaffifin.mp3", "084 Suarh Al Inshiqaq.mp3",
"085 Surah Burooj.mp3", "086 Surah At-Tariq.mp3", "087 Surah Al Ala.mp3", "088 Surah Al Ghashiya.mp3",
"089 Surah Al-Fajr.mp3", "090 Surah Al Balad.mp3", "091 Surah Ash-Shams.mp3", "092 Surah Al-Lail.mp3",
"093 Surah Ad-Duha.mp3", "094 Surah Al Ash Sharh .mp3", "095 Surah At-Tin.mp3", "096 Surah Al-Alaq.mp3",
"097 Surah Al-Qadr.mp3", "098 Surat Al Bayyinah.mp3", "099 Surah Al-Zilzala.mp3", "100 Surah Al-Adiyat.mp3",
"101 Surah Al-Qariah.mp3", "102 Surah At Takasur.mp3", "103 Surah Al-Asr.mp3", "104 Surah Al-Humazah.mp3",
"105 Surah Al-Fil.mp3", "106 Surah Al-Quraish.mp3", "107 Surah Al Maun.mp3", "108 Surah Kausar - wi.mp3",
"109 Surah Al-Kafirun.mp3", "110 Surah An-Nasr.mp3", "111 Surah Al-Lahab.mp3", "112 Surah Al-Ikhlas.mp3",
"113 Surah Al-Falaq.mp3", "114 Surah An-Nas.mp3"
}
end
return _lazyCache.urdu
end
M.buildUrduSurahUrl = function(surahIdx)
local fn = M.urduTranslationFiles()[surahIdx]
if not fn then return nil end
return URLBASES.urdu .. fn:gsub(" ", "%%20")
end
local function urlEncodeBytes(str)
return (str:gsub("[^%w%-%.%_%~]", function(c) return string.format("%%%02X", string.byte(c)) end))
end
M.hindiTranslationFiles = function()
if not _lazyCache.hindi then
_lazyCache.hindi = {
"001 - Al-Fatihah ( The Opening ) - سورة الفاتحة.mp3", "002 - Al-Baqarah ( The Cow ) - سورة البقرة.mp3",
"003 - Al-Imran ( The Family of Imran ) - سورة آل عمران.mp3", "004 - An-Nisa ( The Women ) - سورة النساء.mp3",
"005 - Al-Maidah ( The Table spread with Food ) - سورة المائدة.mp3", "006 - Al-An'am ( The Cattle ) - سورة الأنعام.mp3",
"007 - Al-A'raf (The Heights ) - سورة الأعراف.mp3", "008 - Al-Anfal ( The Spoils of War ) - سورة الأنفال.mp3",
"009 - At-Taubah ( The Repentance ) - سورة التوبة.mp3", "010 - Yunus ( Jonah ) - سورة يونس.mp3",
"011 - Hud - سورة هود.mp3", "012 - Yusuf (Joseph ) - سورة يوسف.mp3",
"013 - Ar-Ra'd ( The Thunder ) - سورة الرعد.mp3", "014 - Ibrahim ( Abraham ) - سورة إبراهيم.mp3",
"015 - Al-Hijr ( The Rocky Tract ) - سورة الحجر.mp3", "016 - An-Nahl ( The Bees ) - سورة النحل.mp3",
"017 - Al-Isra ( The Night Journey ) - سورة الإسراء.mp3", "018 - Al-Kahf ( The Cave ) - سورة الكهف.mp3",
"019 - Maryam ( Mary ) - سورة مريم.mp3", "020 - Taha - سورة طه.mp3",
"021 - Al-Anbiya ( The Prophets ) - سورة الأنبياء.mp3", "022 - Al-Hajj ( The Pilgrimage ) - سورة الحج.mp3",
"023 - Al-Mu'minoon ( The Believers ) - سورة المؤمنون.mp3", "024 - An-Noor ( The Light ) - سورة النور.mp3",
"025 - Al-Furqan (The Criterion ) - سورة الفرقان.mp3", "026 - Ash-Shuara ( The Poets ) - سورة الشعراء.mp3",
"027 - An-Naml (The Ants ) - سورة النمل.mp3", "028 - Al-Qasas ( The Stories ) - سورة القصص.mp3",
"029 - Al-Ankaboot ( The Spider ) - سورة العنكبوت.mp3", "030 - Ar-Room ( The Romans ) - سورة الروم.mp3",
"031 - Luqman - سورة لقمان.mp3", "032 - As-Sajdah ( The Prostration ) - سورة السجدة.mp3",
"033 - Al-Ahzab ( The Combined Forces ) - سورة الأحزاب.mp3", "034 - Saba ( Sheba ) - سورة سبأ.mp3",
"035 - Fatir ( The Orignator ) - سورة فاطر.mp3", "036 - Ya-seen - سورة يس.mp3",
"037 - As-Saaffat ( Those Ranges in Ranks ) - سورة الصافات.mp3", "038 - Sad ( The Letter Sad ) - سورة ص.mp3",
"039 - Az-Zumar ( The Groups ) - سورة الزمر.mp3", "040 - Ghafir ( The Forgiver God ) - سورة غافر.mp3",
"041 - Fussilat ( Explained in Detail ) - سورة فصلت.mp3", "042 - Ash-Shura (Consultation ) - سورة الشورى.mp3",
"043 - Az-Zukhruf ( The Gold Adornment ) - سورة الزخرف.mp3", "044 - Ad-Dukhan ( The Smoke ) - سورة الدخان.mp3",
"045 - Al-Jathiya ( Crouching ) - سورة الجاثية.mp3", "046 - Al-Ahqaf ( The Curved Sand-hills ) - سورة الأحقاف.mp3",
"047 - Muhammad - سورة محمد.mp3", "048 - Al-Fath ( The Victory ) - سورة الفتح.mp3",
"049 - Al-Hujurat ( The Dwellings ) - سورة الحجرات.mp3", "050 - Qaf ( The Letter Qaf ) - سورة ق.mp3",
"051 - Adh-Dhariyat ( The Wind that Scatter ) - سورة الذاريات.mp3", "052 - At-Tur ( The Mount ) - سورة الطور.mp3",
"053 - An-Najm ( The Star ) - سورة النجم.mp3", "054 - Al-Qamar ( The Moon ) - سورة القمر.mp3",
"055 - Ar-Rahman ( The Most Graciouse ) - سورة الرحمن.mp3", "056 - Al-Waqi'ah ( The Event ) - سورة الواقعة.mp3",
"057 - Al-Hadid ( The Iron ) - سورة الحديد.mp3", "058 - Al-Mujadilah ( She That Disputeth ) - سورة المجادلة.mp3",
"059 - Al-Hashr ( The Gathering ) - سورة الحشر.mp3", "060 - Al-Mumtahanah ( The Woman to be examined ) - سورة الممتحنة.mp3",
"061 - As-Saff ( The Row ) - سورة الصف.mp3", "062 - Al-Jumu'ah ( Friday ) - سورة الجمعة.mp3",
"063 - Al-Munafiqoon ( The Hypocrites ) - سورة المنافقون.mp3", "064 - At-Taghabun ( Mutual Loss & Gain ) - سورة التغابن.mp3",
"065 - At-Talaq ( The Divorce ) - سورة الطلاق.mp3", "066 - At-Tahrim ( The Prohibition ) - سورة التحريم.mp3",
"067 - Al-Mulk ( Dominion ) - سورة الملك.mp3", "068 - Al-Qalam ( The Pen ) - سورة القلم.mp3",
"069 - Al-Haaqqah ( The Inevitable ) - سورة الحاقة.mp3", "070 - Al-Ma'arij (The Ways of Ascent ) - سورة المعارج.mp3",
"071 - Nooh - سورة نوح.mp3", "072 - Al-Jinn ( The Jinn ) - سورة الجن.mp3",
"073 - Al-Muzzammil (The One wrapped in Garments) - سورة المزمل.mp3", "074 - Al-Muddaththir ( The One Enveloped ) - سورة المدثر.mp3",
"075 - Al-Qiyamah ( The Resurrection ) - سورة القيامة.mp3", "076 - Al-Insan ( Man ) - سورة الإنسان.mp3",
"077 - Al-Mursalat ( Those sent forth ) - سورة المرسلات.mp3", "078 - An-Naba' ( The Great News ) - سورة النبأ.mp3",
"079 - An-Nazi'at ( Those who Pull Out ) - سورة النازعات.mp3", "080 - Abasa ( He frowned ) - سورة عبس.mp3",
"081 - At-Takwir ( The Overthrowing ) - سورة التكوير.mp3", "082 - Al-Infitar ( The Cleaving ) - سورة الانفطار.mp3",
"083 - Al-Mutaffifin (Those Who Deal in Fraud) - سورة المطففين.mp3", "084 - Al-Inshiqaq (The Splitting Asunder) - سورة الانشقاق.mp3",
"085 - Al-Burooj ( The Big Stars ) - سورة البروج.mp3", "086 - At-Tariq ( The Night-Comer ) - سورة الطارق.mp3",
"087 - Al-A'la ( The Most High ) - سورة الأعلى.mp3", "088 - Al-Ghashiya ( The Overwhelming ) - سورة الغاشية.mp3",
"089 - Al-Fajr ( The Dawn ) - سورة الفجر.mp3", "090 - Al-Balad ( The City ) - سورة البلد.mp3",
"091 - Ash-Shams ( The Sun ) - سورة الشمس.mp3", "092 - Al-Layl ( The Night ) - سورة الليل.mp3",
"093 - Ad-Dhuha ( The Forenoon ) - سورة الضحى.mp3", "094 - As-Sharh ( The Opening Forth) - سورة الشرح.mp3",
"095 - At-Tin ( The Fig ) - سورة التين.mp3", "096 - Al-'alaq ( The Clot ) - سورة العلق.mp3",
"097 - Al-Qadr ( The Night of Decree ) - سورة القدر.mp3", "098 - Al-Bayyinah ( The Clear Evidence ) - سورة البينة.mp3",
"099 - Az-Zalzalah ( The Earthquake ) - سورة الزلزلة.mp3", "100 - Al-'adiyat ( Those That Run ) - سورة العاديات.mp3",
"101 - Al-Qari'ah ( The Striking Hour ) - سورة القارعة.mp3", "102 - At-Takathur ( The piling Up ) - سورة التكاثر.mp3",
"103 - Al-Asr ( The Time ) - سورة العصر.mp3", "104 - Al-Humazah ( The Slanderer ) - سورة الهمزة.mp3",
"105 - Al-Fil ( The Elephant ) - سورة الفيل.mp3", "106 - Quraish - سورة قريش.mp3",
"107 - Al-Ma'un ( Small Kindnesses ) - سورة الماعون.mp3", "108 - Al-Kauthor ( A River in Paradise) - سورة الكوثر.mp3",
"109 - Al-Kafiroon ( The Disbelievers ) - سورة الكافرون.mp3", "110 - An-Nasr ( The Help ) - سورة النصر.mp3",
"111 - Al-Masad ( The Palm Fibre ) - سورة المسد.mp3", "112 - Al-Ikhlas ( Sincerity ) - سورة الإخلاص.mp3",
"113 - Al-Falaq ( The Daybreak ) - سورة الفلق.mp3", "114 - An-Nas ( Mankind ) - سورة الناس.mp3"
}
end
return _lazyCache.hindi
end
M.buildHindiSurahUrl = function(surahIdx)
local fn = M.hindiTranslationFiles()[surahIdx]
if not fn then return nil end
return URLBASES.hindi .. urlEncodeBytes(fn)
end
M.punjabiTranslationFiles = function() return M.hindiTranslationFiles() end
M.buildPunjabiSurahUrl = function(surahIdx)
local fn = M.punjabiTranslationFiles()[surahIdx]
if not fn then return nil end
return URLBASES.punjabi .. urlEncodeBytes(fn)
end
M.englishTranslationFiles = function()
if not _lazyCache.english then
_lazyCache.english = {
"001 - Al-Fatihah (The Opening).mp3", "002 - Al-Baqarah (The Cow).mp3", "003 - Al-Imran (The Family of Imran).mp3",
"004 - An-Nisa (Women).mp3", "005 - Al-Maidah (The Table Spread).mp3", "006 - Al-Anam (The Cattle).mp3",
"007 - Al-Araf (The Heights).mp3", "008 - Al-Anfal (The Spoils of War).mp3", "009 - At-Tawbah (Repentance).mp3",
"010 - Yunus (Jonah).mp3", "011 - Hud (Hud).mp3", "012 - Yusuf (Joseph).mp3",
"013 - Ar-Rad (Thunder).mp3", "014 - Ibrahim (Abraham).mp3", "015 - Al-Hijr (The Stoneland).mp3",
"016 - An-Nahl (The Bees).mp3", "017 - Al-Isra (The Night Journey).mp3", "018 - Al-Kahf (The Cave).mp3",
"019 - Maryam (Mary).mp3", "020 - Ta Ha (Ta Ha).mp3", "021 - Al-Anbiya (The Prophets).mp3",
"022 - Al-Hajj (The Pilgrimage).mp3", "023 - Al-Muminun (The Believers).mp3", "024 - An-Nur (The Light).mp3",
"025 - Al-Furqan (The Criterion).mp3", "026 - Ash-Shuara (The Poets).mp3", "027 - An-Naml (The Ants).mp3",
"028 - Al-Qasas (The Narrative).mp3", "029 - Al-Ankabut (The Spider).mp3", "030 - Ar-Rum (The Romans).mp3",
"031 - Luqman (Luqman).mp3", "032 - As-Sajdah (The Prostration).mp3", "033 - Al-Ahzab (The Combined Forces).mp3",
"034 - Saba (Sheba).mp3", "035 - Al-Fatir (The Originator).mp3", "036 - Ya Sin (Ya Sin).mp3",
"037 - As-Saffat (Those Ranged in Ranks).mp3", "038 - Sad (Sad).mp3", "039 - Az-Zumar (The Groups).mp3",
"040 - Ghafir (The Forgiver).mp3", "041 - Fussilat (Explained in Detail).mp3", "042 - Ash-Shura (The Consultation).mp3",
"043 - Az-Zukhruf (Ornaments of Gold).mp3", "044 - Ad-Dukhan (The Smoke).mp3", "045 - Al-Jathiyah (The Kneeling).mp3",
"046 - Al-Ahqaf (The Sandhills).mp3", "047 - Muhammad (Muhammad).mp3", "048 - Al-Fath (The Victory).mp3",
"049 - Al-Hujurat (The Chambers).mp3", "050 - Qaf (Qaf).mp3", "051 - Ad-Dhariyat (The Winnowing Winds).mp3",
"052 - At-Tur (The Mount).mp3", "053 - An-Najm (The Star).mp3", "054 - Al-Qamar (The Moon).mp3",
"055 - Ar-Rahman (The Beneficent).mp3", "056 - Al-Waqiah (The Inevitable Event).mp3", "057 - Al-Hadid (The Iron).mp3",
"058 - Al-Mujadilah (The Pleading Woman).mp3", "059 - Al-Hashr (The Gathering).mp3", "060 - Al-Mumtahanah (The Woman to be Examined).mp3",
"061 - As-Saff (The Ranks).mp3", "062 - Al-Jumuah (Friday Prayer).mp3", "063 - Al-Munafiqun (The Hypocrites).mp3",
"064 - At-Taghabun (The Manifestation of Losses).mp3", "065 - At-Talaq (Divorce).mp3", "066 - At-Tahrim (The Prohibition).mp3",
"067- Al-Mulk (The Sovereignty).mp3", "068 - Al-Qalam (The Pen).mp3", "069 - Al-Haqqah (The Inevitable Truth).mp3",
"070 - Al-Maarij (The Ways of Ascent).mp3", "071 - Nuh (Noah).mp3", "072 - Al-Jinn (The Jinn).mp3",
"073 - Al-Muzzammil (The Enshrouded).mp3", "074 - Al-Muddaththir (The Cloaked One).mp3", "075 - Al-Qiyamah (The Resurrection).mp3",
"076 - Al-Insan (Man).mp3", "077 - Al-Mursalat (Winds Sent Forth).mp3", "078 - An-Naba (The Tidings).mp3",
"079 - An-Naziat (Those Who Drag Forth).mp3", "080 - Abasa (He Frowned).mp3", "081 - At-Takwir (The Overthrowing).mp3",
"082 - Al-Infitar (The Cleaving).mp3", "083 - Al-Mutaffifin (The Defrauders).mp3", "084 - Al-Inshiqaq (The Cracking).mp3",
"085 - Al-Buruj (The Constellations).mp3", "086 - At-Tariq (The Night-Comer).mp3", "087 - Al-Ala (The Most High).mp3",
"088 - Al-Ghashiyah (The Overwhelming Event).mp3", "089 - Al-Fajr (The Dawn).mp3", "090 - Al-Balad (The City).mp3",
"091 - Ash-Shams (The Sun).mp3", "092 - Al-Layl (The Night).mp3", "093 - Ad-Duha (The Morning Brightness).mp3",
"094 - Ash-Sharh (The Relief).mp3", "095 - At-Tin (The Fig).mp3", "096 - Al-Alaq (The Clot).mp3",
"097 - Al-Qadr (Power, Fate).mp3", "098 - Al-Bayyinah (The Clear Evidence).mp3", "099 - Az-Zalzala (The Earthquake).mp3",
"100 - Al-Adiyat (The Charging Horses).mp3", "101 - Al-Qariah (The Striking Calamity).mp3", "102 - At-Takathur (Rivalry In Worldly Increase).mp3",
"103 - Al-Asr (The Time).mp3", "104 - Al-Humazah (The Slanderer).mp3", "105 - Al-Fil (The Elephant).mp3",
"106 - Quraysh (Quraish).mp3", "107 - Al-Maun (Small Kindnesses).mp3", "108 - Al-Kawthar (Abundance).mp3",
"109 - Al-Kafirun (The Disbelievers).mp3", "110 - An-Nasr (The Help).mp3", "111 - Al-Masad (The Plaited Rope).mp3",
"112 - Al-Ikhlas (Purity of Faith).mp3", "113 - Al-Falaq (The Daybreak).mp3", "114 - An-Nas (Mankind).mp3"
}
end
return _lazyCache.english
end
M.buildEnglishSurahUrl = function(surahIdx)
local fn = M.englishTranslationFiles()[surahIdx]
if not fn then return nil end
return URLBASES.english .. urlEncodeBytes(fn)
end
M.buildSindhiSurahUrl = function(surahIdx)
local fn = M.hindiTranslationFiles()[surahIdx]
if not fn then return nil end
return URLBASES.sindhi .. urlEncodeBytes(fn)
end
V25.items["EN"] = "Qur_aan"
V25.files["EN"] = {
["1"] = "001-SurahAl-faatiha.mp3",
["2"] = "002-SurahAl-baqarah.mp3",
["3"] = "003-SurahAal-imraan.mp3",
["4"] = "004-SurahAn-nisaa.mp3",
["5"] = "005-SurahAl-maaidah.mp3",
["6"] = "006-SurahAl-anaam.mp3",
["7"] = "007-SurahAl-araaf.mp3",
["8"] = "008-SurahAl-anfaal.mp3",
["9"] = "009-SurahAt-tawbah.mp3",
["10"] = "010-SurahYunus.mp3",
["11"] = "011-SurahHud.mp3",
["12"] = "012-SurahYusuf.mp3",
["13"] = "013-SurahAr-rad.mp3",
["14"] = "014-SurahIbraheem.mp3",
["15"] = "015-SurahAl-hijr.mp3",
["16"] = "016-SurahAn-nahl.mp3",
["17"] = "017-SurahAl-israa.mp3",
["18"] = "018-SurahAl-kahf.mp3",
["19"] = "019-SurahMaryam.mp3",
["20"] = "020-SurahTaa-haa.mp3",
["21"] = "021-SurahAl-anbiyaa.mp3",
["22"] = "022-SurahAl-hajj.mp3",
["23"] = "023-SurahAl-muminun.mp3",
["24"] = "024-SurahAn-nur.mp3",
["25"] = "025-SurahAl-furqaan.mp3",
["26"] = "026-SurahAsh-shuaraa.mp3",
["27"] = "027-SurahAn-naml.mp3",
["28"] = "028-SurahAl-qasas.mp3",
["29"] = "029-SurahAl-ankabut.mp3",
["30"] = "030-SurahAr-rum.mp3",
["31"] = "031-SurahLuqmaan.mp3",
["32"] = "032-SurahAs-sajdah.mp3",
["33"] = "033-SurahAl-ahzaab.mp3",
["34"] = "034-SurahSaba.mp3",
["35"] = "035-SurahFaatir.mp3",
["36"] = "036-SurahYaa-seen.mp3",
["37"] = "037-SurahAs-saaffaat.mp3",
["38"] = "038-SurahSaad.mp3",
["39"] = "039-SurahAz-zumar.mp3",
["40"] = "040-SurahGhaafir.mp3",
["41"] = "041-SurahFussilat.mp3",
["42"] = "042-SurahAsh-shura.mp3",
["43"] = "043-SurahAz-zukhruf.mp3",
["44"] = "044-SurahAd-dukhaan.mp3",
["45"] = "045-SurahAl-jaathiyah.mp3",
["46"] = "046-SurahAl-ahqaaf.mp3",
["47"] = "047-SurahMuhammad.mp3",
["48"] = "048-SurahAl-fath.mp3",
["49"] = "049-SurahAl-hujuraat.mp3",
["50"] = "050-SurahQaaf.mp3",
["51"] = "051-SurahAdh-dhaariyaat.mp3",
["52"] = "052-SurahAt-tur.mp3",
["53"] = "053-SurahAn-najm.mp3",
["54"] = "054-SurahAl-qamar.mp3",
["55"] = "055-SurahAr-rahmaan.mp3",
["56"] = "056-SurahAl-waaqiah.mp3",
["57"] = "057-SurahAl-hadeed.mp3",
["58"] = "058-SurahAl-mujaadalah.mp3",
["59"] = "059-SurahAl-hashr.mp3",
["60"] = "060-SurahAl-mumtahinah.mp3",
["61"] = "061-SurahAs-saff.mp3",
["62"] = "062-SurahAl-jumuah.mp3",
["63"] = "063-SurahAl-munaafiqun.mp3",
["64"] = "064-SurahAt-taghaabun.mp3",
["65"] = "065-SurahAt-talaaq.mp3",
["66"] = "066-SurahAt-tahreem.mp3",
["67"] = "067-SurahAl-mulk.mp3",
["68"] = "068-SurahAl-qalam.mp3",
["69"] = "069-SurahAl-haaqqah.mp3",
["70"] = "070-SurahAl-maaarij.mp3",
["71"] = "071-SurahNuh.mp3",
["72"] = "072-SurahAl-jinn.mp3",
["73"] = "073-SurahAl-muzzammil.mp3",
["74"] = "074-SurahAl-muddaththir.mp3",
["75"] = "075-SurahAl-qiyaamah.mp3",
["76"] = "076-SurahAl-insaan.mp3",
["77"] = "077-SurahAl-mursalaat.mp3",
["78"] = "078-SurahAn-naba.mp3",
["79"] = "079-SurahAl-naaziaat.mp3",
["80"] = "080-Surahabasa.mp3",
["81"] = "081-SurahAt-takweer.mp3",
["82"] = "082-SurahAl-infitaar.mp3",
["83"] = "083-SurahAl-mutaffifeen.mp3",
["84"] = "084-SurahInshiqaaq.mp3",
["85"] = "085-SurahAl-burooj.mp3",
["86"] = "086-SurahAt-taariq.mp3",
["87"] = "087-SurahAl-alaa.mp3",
["88"] = "088-SurahAl-ghaashiyah.mp3",
["89"] = "089-SurahAl-fajr.mp3",
["90"] = "090-SurahAl-balad.mp3",
["91"] = "091-SurahAsh-shams.mp3",
["92"] = "092-SurahAl-layl.mp3",
["93"] = "093-SurahAd-duha.mp3",
["94"] = "094-SurahAsh-sharh.mp3",
["95"] = "095-SurahAt-teen.mp3",
["96"] = "096-SurahAl-alaq.mp3",
["97"] = "097-SurahAl-qadr.mp3",
["98"] = "098-SurahAl-bayyinah.mp3",
["99"] = "099-SurahAz-zalzaalah.mp3",
["100"] = "100-SurahAl-aadiyaat.mp3",
["101"] = "101-SurahAl-qaariah.mp3",
["102"] = "102-SurahAt-takaathur.mp3",
["103"] = "103-SurahAl-asr.mp3",
["104"] = "104-SurahAl-humazah.mp3",
["105"] = "105-SurahAl-feel.mp3",
["106"] = "106-SurahQuraysh.mp3",
["107"] = "107-SurahAl-maaun.mp3",
["108"] = "108-SurahAl-kawthar.mp3",
["109"] = "109-SurahAl-kaafirun.mp3",
["110"] = "110-SurahAn-nasr.mp3",
["111"] = "111-SurahAl-masad.mp3",
["112"] = "112-SurahAl-ikhlaas.mp3",
["113"] = "113-SurahAl-falaq.mp3",
["114"] = "114-SurahAn-naas.mp3",
}
V25.items["EN2"] = "MishaariRashid-TheNobelQuran-English"
V25.files["EN2"] = {
["1"] = "001 surah_al_fatihah.mp3",
["2"] = "002 surah_al_baqarah.mp3",
["3"] = "003 surah_al_imran.mp3",
["4"] = "004 surah_an_nisa.mp3",
["5"] = "005 surah_al_maidah.mp3",
["6"] = "006 surah_al_anam.mp3",
["7"] = "007 surah_al_araf.mp3",
["8"] = "008 surah_al_anfal.mp3",
["9"] = "009 surah_at_tawbah.mp3",
["10"] = "010 surah_yunus.mp3",
["11"] = "011 surah_hud.mp3",
["12"] = "012 surah_yusuf.mp3",
["13"] = "013 surah_ar_rad.mp3",
["14"] = "014 surah_ibrahim.mp3",
["15"] = "015 surah_al_hijr.mp3",
["16"] = "016 surah_an_nahl.mp3",
["17"] = "017 surah_al_isra.mp3",
["18"] = "018 surah_al_kahf.mp3",
["19"] = "019 surah_maryam.mp3",
["20"] = "020 surah_ta_ha.mp3",
["21"] = "021 surah_al_anbiya.mp3",
["22"] = "022 surah_al_hajj.mp3",
["23"] = "023 surah_al_muminun.mp3",
["24"] = "024 surah_an_nur.mp3",
["25"] = "025 surah_al_furqan.mp3",
["26"] = "026 surah_ash_shuara.mp3",
["27"] = "027 surah_an_naml.mp3",
["28"] = "028 surah_al_qasas.mp3",
["29"] = "029 surah_al_ankabut.mp3",
["30"] = "030 surah_ar_rum.mp3",
["31"] = "031 surah_luqman.mp3",
["32"] = "032 surah_as_sajdah.mp3",
["33"] = "033 surah_al_ahzab.mp3",
["34"] = "034 surah_saba.mp3",
["35"] = "035 surah_fatir.mp3",
["36"] = "036 surah_ya_sin.mp3",
["37"] = "037 surah_as_safat.mp3",
["38"] = "038 surah_sad.mp3",
["39"] = "039 surah_az_zumar.mp3",
["40"] = "040 surah_ghafir.mp3",
["41"] = "041 surah_fussilat.mp3",
["42"] = "042 surah_ash_shura.mp3",
["43"] = "043 surah_az_zukhruf.mp3",
["44"] = "044 surah_ad_dukhan.mp3",
["45"] = "045 surah_al_jathiyah.mp3",
["46"] = "046 surah_al_ahqaf.mp3",
["47"] = "047 surah_muhammad.mp3",
["48"] = "048 surah_al_fath.mp3",
["49"] = "049 surah_al_hujurat.mp3",
["50"] = "050 surah_qaf.mp3",
["51"] = "051 surah_adh_dhariyat.mp3",
["52"] = "052 surah_at_tur.mp3",
["53"] = "053 surah_an_najm.mp3",
["54"] = "054 surah_al_qamar.mp3",
["55"] = "055 surah_ar_rahman.mp3",
["56"] = "056 surah_al_waqiah.mp3",
["57"] = "057 surah_al_hadid.mp3",
["58"] = "058 surah_al_mujadilah.mp3",
["59"] = "059 surah_al_hashr.mp3",
["60"] = "060 surah_al_mumtahanah.mp3",
["61"] = "061 surah_as_saff.mp3",
["62"] = "062 surah_al_jumuah.mp3",
["63"] = "063 surah_al_munafiqun.mp3",
["64"] = "064 surah_at_taghabun.mp3",
["65"] = "065 surah_at_talaq.mp3",
["66"] = "066 surah_at_tahrim.mp3",
["67"] = "067 surah_al_mulk.mp3",
["68"] = "068 surah_al_qalam.mp3",
["69"] = "069 surah_al_haqqah.mp3",
["70"] = "070 surah_al_maarij.mp3",
["71"] = "071 surah_nuh.mp3",
["72"] = "072 surah_al_jinn.mp3",
["73"] = "073 surah_al_muzzammil.mp3",
["74"] = "074 surah_al_muddaththir.mp3",
["75"] = "075 surah_al_qiyamah.mp3",
["76"] = "076 surah_al_insan.mp3",
["77"] = "077 surah_al_mursalat.mp3",
["78"] = "078 surah_an_naba.mp3",
["79"] = "079 surah_an_naziat.mp3",
["80"] = "080 surah_abasa.mp3",
["81"] = "081 surah_at_takwir.mp3",
["82"] = "082 surah_al_infitar.mp3",
["83"] = "083 surah_al_mutaffifin.mp3",
["84"] = "084 surah_al_inshiqaq.mp3",
["85"] = "085 surah_al_buruj.mp3",
["86"] = "086 surah_at_tariq.mp3",
["87"] = "087 surah_al_ala.mp3",
["88"] = "088 surah_al_ghashiyah.mp3",
["89"] = "089 surah_al_fajr.mp3",
["90"] = "090 surah_al_balad.mp3",
["91"] = "091 surah_ash_shams.mp3",
["92"] = "092 surah_al_layl.mp3",
["93"] = "093 surah_ad_duha.mp3",
["94"] = "094 surah_ash_sharh.mp3",
["95"] = "095 surah_at_tin.mp3",
["96"] = "096 surah_al_alaq.mp3",
["97"] = "097 surah_al_qadr.mp3",
["98"] = "098 surah_al_bayyinah.mp3",
["99"] = "099 surah_az_zalzalah.mp3",
["100"] = "100 surah_al_adiyat.mp3",
["101"] = "101 surah_al_qariah.mp3",
["102"] = "102 surah_at_takathur.mp3",
["103"] = "103 surah_al_asr.mp3",
["104"] = "104 surah_al_humazah.mp3",
["105"] = "105 surah_al_fil.mp3",
["106"] = "106 surah_quraysh.mp3",
["107"] = "107 surah_al_maun.mp3",
["108"] = "108 surah_al_kawthar.mp3",
["109"] = "109 surah_al_kafirun.mp3",
["110"] = "110 surah_an_nasr.mp3",
["111"] = "111 surah_al_masad.mp3",
["112"] = "112 surah_al_ikhlas.mp3",
["113"] = "113 surah_al_falaq.mp3",
["114"] = "114 surah_an_nas.mp3",
}
V25.items["HI"] = "hindi-meal"
V25.files["HI"] = {
["1"] = "001-Al-Fatiha.mp3",
["2"] = "002-Al-Baqarah2.mp3",
["3"] = "003-Al-imran.mp3",
["4"] = "004-An-Nisa.mp3",
["5"] = "005-Al-Maidah.mp3",
["6"] = "006-Enam.mp3",
["7"] = "007-Al-Araf.mp3",
["8"] = "008-Al-Anfal.mp3",
["9"] = "009.At-Taubah.mp3",
["10"] = "010-Yunus.mp3",
["11"] = "011-Hud.mp3",
["12"] = "012-Yusuf.mp3",
["13"] = "013-Ar-Rad.mp3",
["14"] = "014-ibrahim.mp3",
["15"] = "015-Al-Hijr.mp3",
["16"] = "016-An-Nahl.mp3",
["17"] = "017-Al-Isra.mp3",
["18"] = "018-Al-Kahf.mp3",
["19"] = "019.Maryam.mp3",
["20"] = "020.Ta-Ha.mp3",
["21"] = "021-Al-Anbiya.mp3",
["22"] = "022-Al-Hajj.mp3",
["23"] = "023-Al-Mu-minun.mp3",
["24"] = "024-An-Nur.mp3",
["25"] = "025-Al-Furqan.mp3",
["26"] = "026-Ash-Shu-ara.mp3",
["27"] = "027-An-Naml.mp3",
["28"] = "028-Al-Qasas.mp3",
["29"] = "029-Al-Ankabut.mp3",
["30"] = "030-Ar-Rum.mp3",
["31"] = "031-Luqman.mp3",
["32"] = "032-As-Sajdah.mp3",
["33"] = "033-Al-Ahzab.mp3",
["34"] = "034-Saba..mp3",
["35"] = "035-Fatir.mp3",
["36"] = "036-Ya-Sin.mp3",
["37"] = "037-As-Saffat.mp3",
["38"] = "038-Sad.mp3",
["39"] = "039-Az-Zumar.mp3",
["40"] = "040-Mumin-Ghafir.mp3",
["41"] = "041-Fussilat.mp3",
["42"] = "042-Ash-Shura.mp3",
["43"] = "043-Az-Zukhruf.mp3",
["44"] = "044-Ad-Dukhan.mp3",
["45"] = "045-Al-Jathiyah.mp3",
["46"] = "046-Al-Ahqaf.mp3",
["47"] = "047-Muhammad.mp3",
["48"] = "048-Al-Fath.mp3",
["49"] = "049-Al-Hujurat.mp3",
["50"] = "050-Qaf.mp3",
["51"] = "051-Adh-Dhariyat.mp3",
["52"] = "052-At-Tur.mp3",
["53"] = "053-An-Najm.mp3",
["54"] = "054-Al-Qamar.mp3",
["55"] = "055-Ar-Rahman.mp3",
["56"] = "056-Al-Waqi-ah.mp3",
["57"] = "057-Al-Hadid.mp3",
["58"] = "058-Al-Mujadilah.mp3",
["59"] = "059-Al-Hashr.mp3",
["60"] = "060-Al-Mumtahanah.mp3",
["61"] = "061-As-Saff.mp3",
["62"] = "062-Al-Jumu-ah.mp3",
["63"] = "063-Al-Munafiqun.mp3",
["64"] = "064-At-Taghabun.mp3",
["65"] = "065-At-Talaq.mp3",
["66"] = "066-At-Tahrim.mp3",
["67"] = "067-Al-Mulk.mp3",
["68"] = "068-Al-Qalam.mp3",
["69"] = "069-Al-Haqqah.mp3",
["70"] = "070-Al-Maarij.mp3",
["71"] = "071-Nuh.mp3",
["72"] = "072-Al-Jinn.mp3",
["73"] = "073-Al-Muzzammil.mp3",
["74"] = "074-Al-Muddaththir.mp3",
["75"] = "075-Al-Qiyamah.mp3",
["76"] = "076-Al-Insan.mp3",
["77"] = "077-Al-Mursalat.mp3",
["78"] = "078-Al-Naba.mp3",
["79"] = "079-Al-Naaze.mp3",
["80"] = "080-Abasa.mp3",
["81"] = "081-Al-Takweer.mp3",
["82"] = "082-Al-Infitaar.mp3",
["83"] = "083-Al-Mutaffifeen.mp3",
["84"] = "084-Al-Inshiqaaq.mp3",
["85"] = "085-Al-Burooj.mp3",
["86"] = "086-Al-Taareq.mp3",
["87"] = "087-Al-A-alaa.mp3",
["88"] = "088-Al-Ghaasheyah.mp3",
["89"] = "089-Al-Fajr.mp3",
["90"] = "090-Al-Balad.mp3",
["91"] = "091-Al-Shams.mp3",
["92"] = "092-Al-Layl.mp3",
["93"] = "093-Al-Duhaa.mp3",
["94"] = "094-Al-insirah.mp3",
["95"] = "095-Al-Teen.mp3",
["96"] = "096-Al-Alaq.mp3",
["97"] = "097-Al-Qadr.mp3",
["98"] = "098-Al-Bayyinah.mp3",
["99"] = "099-Al-Zilzalaha.mp3",
["100"] = "100-Al-Aadeyat.mp3",
["101"] = "101-Al-Qaare-ah.mp3",
["102"] = "102-Al-Takasur.mp3",
["103"] = "103-Al-Asr.mp3",
["104"] = "104-Al-Humazah.mp3",
["105"] = "105-Al-Feel.mp3",
["106"] = "106-Al-Quraishinsirah.mp3",
["107"] = "107-Al-Maa-oon.mp3",
["108"] = "108-Al-Kausar.mp3",
["109"] = "109-Al-Kaaferoon.mp3",
["110"] = "110-Al-Nasr.mp3",
["111"] = "111-Al-Masad.mp3",
["112"] = "112-Al-Ikhlaas.mp3",
["113"] = "113-Al-Falaq.mp3",
["114"] = "114-Al-Naas.mp3",
}
V25.items["BN"] = "AlQuranWithBengaliBanglaTranslation-ReciterMisharyRashidAl-Afasy"
V25.files["BN"] = {
["1"] = "001 - Al-Fatihah ( The Opening ) - سورة الفاتحة.mp3",
["2"] = "002 - Al-Baqarah ( The Cow ) - سورة البقرة.mp3",
["3"] = "003 - Al-Imran ( The Family of Imran ) - سورة آل عمران.mp3",
["4"] = "004 - An-Nisa ( The Women ) - سورة النساء.mp3",
["5"] = "005 - Al-Maidah ( The Table spread with Food ) - سورة المائدة.mp3",
["6"] = "006 - Al-An'am ( The Cattle ) - سورة الأنعام.mp3",
["7"] = "007 - Al-A'raf (The Heights ) - سورة الأعراف.mp3",
["8"] = "008 - Al-Anfal ( The Spoils of War ) - سورة الأنفال.mp3",
["9"] = "009 - At-Taubah ( The Repentance ) - سورة التوبة.mp3",
["10"] = "010 - Yunus ( Jonah ) - سورة يونس.mp3",
["11"] = "011 - Hud - سورة هود.mp3",
["12"] = "012 - Yusuf (Joseph ) - سورة يوسف.mp3",
["13"] = "013 - Ar-Ra'd ( The Thunder ) - سورة الرعد.mp3",
["14"] = "014 - Ibrahim ( Abraham ) - سورة إبراهيم.mp3",
["15"] = "015 - Al-Hijr ( The Rocky Tract ) - سورة الحجر.mp3",
["16"] = "016 - An-Nahl ( The Bees ) - سورة النحل.mp3",
["17"] = "017 - Al-Isra ( The Night Journey ) - سورة الإسراء.mp3",
["18"] = "018 - Al-Kahf ( The Cave ) - سورة الكهف.mp3",
["19"] = "019 - Maryam ( Mary ) - سورة مريم.mp3",
["20"] = "020 - Taha - سورة طه.mp3",
["21"] = "021 - Al-Anbiya ( The Prophets ) - سورة الأنبياء.mp3",
["22"] = "022 - Al-Hajj ( The Pilgrimage ) - سورة الحج.mp3",
["23"] = "023 - Al-Mu'minoon ( The Believers ) - سورة المؤمنون.mp3",
["24"] = "024 - An-Noor ( The Light ) - سورة النور.mp3",
["25"] = "025 - Al-Furqan (The Criterion ) - سورة الفرقان.mp3",
["26"] = "026 - Ash-Shuara ( The Poets ) - سورة الشعراء.mp3",
["27"] = "027 - An-Naml (The Ants ) - سورة النمل.mp3",
["28"] = "028 - Al-Qasas ( The Stories ) - سورة القصص.mp3",
["29"] = "029 - Al-Ankaboot ( The Spider ) - سورة العنكبوت.mp3",
["30"] = "030 - Ar-Room ( The Romans ) - سورة الروم.mp3",
["31"] = "031 - Luqman - سورة لقمان.mp3",
["32"] = "032 - As-Sajdah ( The Prostration ) - سورة السجدة.mp3",
["33"] = "033 - Al-Ahzab ( The Combined Forces ) - سورة الأحزاب.mp3",
["34"] = "034 - Saba ( Sheba ) - سورة سبأ.mp3",
["35"] = "035 - Fatir ( The Orignator ) - سورة فاطر.mp3",
["36"] = "036 - Ya-seen - سورة يس.mp3",
["37"] = "037 - As-Saaffat ( Those Ranges in Ranks ) - سورة الصافات.mp3",
["38"] = "038 - Sad ( The Letter Sad ) - سورة ص.mp3",
["39"] = "039 - Az-Zumar ( The Groups ) - سورة الزمر.mp3",
["40"] = "040 - Ghafir ( The Forgiver God ) - سورة غافر.mp3",
["41"] = "041 - Fussilat ( Explained in Detail ) - سورة فصلت.mp3",
["42"] = "042 - Ash-Shura (Consultation ) - سورة الشورى.mp3",
["43"] = "043 - Az-Zukhruf ( The Gold Adornment ) - سورة الزخرف.mp3",
["44"] = "044 - Ad-Dukhan ( The Smoke ) - سورة الدخان.mp3",
["45"] = "045 - Al-Jathiya ( Crouching ) - سورة الجاثية.mp3",
["46"] = "046 - Al-Ahqaf ( The Curved Sand-hills ) - سورة الأحقاف.mp3",
["47"] = "047 - Muhammad - سورة محمد.mp3",
["48"] = "048 - Al-Fath ( The Victory ) - سورة الفتح.mp3",
["49"] = "049 - Al-Hujurat ( The Dwellings ) - سورة الحجرات.mp3",
["50"] = "050 - Qaf ( The Letter Qaf ) - سورة ق.mp3",
["51"] = "051 - Adh-Dhariyat ( The Wind that Scatter ) - سورة الذاريات.mp3",
["52"] = "052 - At-Tur ( The Mount ) - سورة الطور.mp3",
["53"] = "053 - An-Najm ( The Star ) - سورة النجم.mp3",
["54"] = "054 - Al-Qamar ( The Moon ) - سورة القمر.mp3",
["55"] = "055 - Ar-Rahman ( The Most Graciouse ) - سورة الرحمن.mp3",
["56"] = "056 - Al-Waqi'ah ( The Event ) - سورة الواقعة.mp3",
["57"] = "057 - Al-Hadid ( The Iron ) - سورة الحديد.mp3",
["58"] = "058 - Al-Mujadilah ( She That Disputeth ) - سورة المجادلة.mp3",
["59"] = "059 - Al-Hashr ( The Gathering ) - سورة الحشر.mp3",
["60"] = "060 - Al-Mumtahanah ( The Woman to be examined ) - سورة الممتحنة.mp3",
["61"] = "061 - As-Saff ( The Row ) - سورة الصف.mp3",
["62"] = "062 - Al-Jumu'ah ( Friday ) - سورة الجمعة.mp3",
["63"] = "063 - Al-Munafiqoon ( The Hypocrites ) - سورة المنافقون.mp3",
["64"] = "064 - At-Taghabun ( Mutual Loss & Gain ) - سورة التغابن.mp3",
["65"] = "065 - At-Talaq ( The Divorce ) - سورة الطلاق.mp3",
["66"] = "066 - At-Tahrim ( The Prohibition ) - سورة التحريم.mp3",
["67"] = "067 - Al-Mulk ( Dominion ) - سورة الملك.mp3",
["68"] = "068 - Al-Qalam ( The Pen ) - سورة القلم.mp3",
["69"] = "069 - Al-Haaqqah ( The Inevitable ) - سورة الحاقة.mp3",
["70"] = "070 - Al-Ma'arij (The Ways of Ascent ) - سورة المعارج.mp3",
["71"] = "071 - Nooh - سورة نوح.mp3",
["72"] = "072 - Al-Jinn ( The Jinn ) - سورة الجن.mp3",
["73"] = "073 - Al-Muzzammil (The One wrapped in Garments) - سورة المزمل.mp3",
["74"] = "074 - Al-Muddaththir ( The One Enveloped ) - سورة المدثر.mp3",
["75"] = "075 - Al-Qiyamah ( The Resurrection ) - سورة القيامة.mp3",
["76"] = "076 - Al-Insan ( Man ) - سورة الإنسان.mp3",
["77"] = "077 - Al-Mursalat ( Those sent forth ) - سورة المرسلات.mp3",
["78"] = "078 - An-Naba' ( The Great News ) - سورة النبأ.mp3",
["79"] = "079 - An-Nazi'at ( Those who Pull Out ) - سورة النازعات.mp3",
["80"] = "080 - Abasa ( He frowned ) - سورة عبس.mp3",
["81"] = "081 - At-Takwir ( The Overthrowing ) - سورة التكوير.mp3",
["82"] = "082 - Al-Infitar ( The Cleaving ) - سورة الانفطار.mp3",
["83"] = "083 - Al-Mutaffifin (Those Who Deal in Fraud) - سورة المطففين.mp3",
["84"] = "084 - Al-Inshiqaq (The Splitting Asunder) - سورة الانشقاق.mp3",
["85"] = "085 - Al-Burooj ( The Big Stars ) - سورة البروج.mp3",
["86"] = "086 - At-Tariq ( The Night-Comer ) - سورة الطارق.mp3",
["87"] = "087 - Al-A'la ( The Most High ) - سورة الأعلى.mp3",
["88"] = "088 - Al-Ghashiya ( The Overwhelming ) - سورة الغاشية.mp3",
["89"] = "089 - Al-Fajr ( The Dawn ) - سورة الفجر.mp3",
["90"] = "090 - Al-Balad ( The City ) - سورة البلد.mp3",
["91"] = "091 - Ash-Shams ( The Sun ) - سورة الشمس.mp3",
["92"] = "092 - Al-Layl ( The Night ) - سورة الليل.mp3",
["93"] = "093 - Ad-Dhuha ( The Forenoon ) - سورة الضحى.mp3",
["94"] = "094 - As-Sharh ( The Opening Forth) - سورة الشرح.mp3",
["95"] = "095 - At-Tin ( The Fig ) - سورة التين.mp3",
["96"] = "096 - Al-'alaq ( The Clot ) - سورة العلق.mp3",
["97"] = "097 - Al-Qadr ( The Night of Decree ) - سورة القدر.mp3",
["98"] = "098 - Al-Bayyinah ( The Clear Evidence ) - سورة البينة.mp3",
["99"] = "099 - Az-Zalzalah ( The Earthquake ) - سورة الزلزلة.mp3",
["100"] = "100 - Al-'adiyat ( Those That Run ) - سورة العاديات.mp3",
["101"] = "101 - Al-Qari'ah ( The Striking Hour ) - سورة القارعة.mp3",
["102"] = "102 - At-Takathur ( The piling Up ) - سورة التكاثر.mp3",
["103"] = "103 - Al-Asr ( The Time ) - سورة العصر.mp3",
["104"] = "104 - Al-Humazah ( The Slanderer ) - سورة الهمزة.mp3",
["105"] = "105 - Al-Fil ( The Elephant ) - سورة الفيل.mp3",
["106"] = "106 - Quraish - سورة قريش.mp3",
["107"] = "107 - Al-Ma'un ( Small Kindnesses ) - سورة الماعون.mp3",
["108"] = "108 - Al-Kauthor ( A River in Paradise) - سورة الكوثر.mp3",
["109"] = "109 - Al-Kafiroon ( The Disbelievers ) - سورة الكافرون.mp3",
["110"] = "110 - An-Nasr ( The Help ) - سورة النصر.mp3",
["111"] = "111 - Al-Masad ( The Palm Fibre ) - سورة المسد.mp3",
["112"] = "112 - Al-Ikhlas ( Sincerity ) - سورة الإخلاص.mp3",
["113"] = "113 - Al-Falaq ( The Daybreak ) - سورة الفلق.mp3",
["114"] = "114 - An-Nas ( Mankind ) - سورة الناس.mp3",
}
V25.items["FR"] = "QuranMisharyAlAfasyWithFrenchTranslation"
V25.files["FR"] = {
["1"] = "001.Al-Fatiha.mp3",
["2"] = "002.Al-Baqarah.mp3",
["3"] = "003.Ali-Imran.mp3",
["4"] = "004.An-Nisa.mp3",
["5"] = "005.Al-Maidah.mp3",
["6"] = "006.Al-Anaam.mp3",
["7"] = "007.Al-Araf.mp3",
["8"] = "008.Al-Anfal.mp3",
["9"] = "009.At-Tawbah.mp3",
["10"] = "010.Yunus.mp3",
["11"] = "011.Hud.mp3",
["12"] = "012.Yusuf.mp3",
["13"] = "013.Ar-Raad.mp3",
["14"] = "014.Ibrahim.mp3",
["15"] = "015.Al-Hijr.mp3",
["16"] = "016.An-Nahl.mp3",
["17"] = "017.Al-Isra.mp3",
["18"] = "018.Al-Kahf.mp3",
["19"] = "019.Maryam.mp3",
["20"] = "020.Ta-Ha.mp3",
["21"] = "021.Al-Anbiya.mp3",
["22"] = "022.Al-Hajj.mp3",
["23"] = "023.Al-Muminun.mp3",
["24"] = "024.An-Nur.mp3",
["25"] = "025.Al-Furqan.mp3",
["26"] = "026.As-Shuaraa.mp3",
["27"] = "027.An-Naml.mp3",
["28"] = "028.Al-Qasas.mp3",
["29"] = "029.Al-Ankabut.mp3",
["30"] = "030.Ar-Rum.mp3",
["31"] = "031.Luqman.mp3",
["32"] = "032.As-Sajda.mp3",
["33"] = "033.Al-Ahzab.mp3",
["34"] = "034.Saba.mp3",
["35"] = "035.Fatir.mp3",
["36"] = "036.Ya-Sin.mp3",
["37"] = "037.As-Saffat.mp3",
["38"] = "038.Sad.mp3",
["39"] = "039.Az-Zumar.mp3",
["40"] = "040.Gafir.mp3",
["41"] = "041.Fussilat.mp3",
["42"] = "042.Achoura.mp3",
["43"] = "043.Az-Zukhruf.mp3",
["44"] = "044.Ad-Dukhan.mp3",
["45"] = "045.Al-Jathya.mp3",
["46"] = "046.Al-Ahqaf.mp3",
["47"] = "047.Muhammad.mp3",
["48"] = "048.Al-Fath.mp3",
["49"] = "049.Al-Hujurat.mp3",
["50"] = "050.Qaf.mp3",
["51"] = "051.Ad-Dariyat.mp3",
["52"] = "052.At-Tur.mp3",
["53"] = "053.An-Najm.mp3",
["54"] = "054.Al-Qamar.mp3",
["55"] = "055.Ar-Rahman.mp3",
["56"] = "056.Al-Waqia.mp3",
["57"] = "057.Al-Hadid.mp3",
["58"] = "058.Al-Mujadalah.mp3",
["59"] = "059.Al-Hashr.mp3",
["60"] = "060.Al-Mumtahanah.mp3",
["61"] = "061.As-Saff.mp3",
["62"] = "062.Al-Jumua.mp3",
["63"] = "063.Al-Munafiqun.mp3",
["64"] = "064.At-Tagabun.mp3",
["65"] = "065.At-Talaq.mp3",
["66"] = "066.At-Tahrim.mp3",
["67"] = "067.Al-Mulk.mp3",
["68"] = "068.Al-Qalam.mp3",
["69"] = "069.Al-Haqqah.mp3",
["70"] = "070.Al-Maarij.mp3",
["71"] = "071.Nuh.mp3",
["72"] = "072.Al-Jinn.mp3",
["73"] = "073.Al-Muzzamil.mp3",
["74"] = "074.Al-Muddattir.mp3",
["75"] = "075.Al-Qiyamah.mp3",
["76"] = "076.Al-Insan.mp3",
["77"] = "077.Al-Mursalat.mp3",
["78"] = "078.An-Naba.mp3",
["79"] = "079.An-Naziat.mp3",
["80"] = "080.Abasa.mp3",
["81"] = "081.At-Takwir.mp3",
["82"] = "082.Al-Infitar.mp3",
["83"] = "083.Al-Mutaffifun.mp3",
["84"] = "084.Al-Insiqaq.mp3",
["85"] = "085.Al-Buruj.mp3",
["86"] = "086.At-Tariq.mp3",
["87"] = "087.Al-Ala.mp3",
["88"] = "088.Al-Gashiyah.mp3",
["89"] = "089.Al-Fajr.mp3",
["90"] = "090.Al-Balad.mp3",
["91"] = "091.Ach-Chams.mp3",
["92"] = "092.Al-Layl.mp3",
["93"] = "093.Ad-Duha.mp3",
["94"] = "094.Al-Inshirah.mp3",
["95"] = "095.At-Tin.mp3",
["96"] = "096.Al-Alaq.mp3",
["97"] = "097.Al-Qadr.mp3",
["98"] = "098.Al-Bayyinah.mp3",
["99"] = "099.Az-Zalzalah.mp3",
["100"] = "100.Al-Adiyat.mp3",
["101"] = "101.Al-Qariah.mp3",
["102"] = "102.At-Takatur.mp3",
["103"] = "103.Al-Asr.mp3",
["104"] = "104.Al-Humazah.mp3",
["105"] = "105.Al-Fil.mp3",
["106"] = "106.Qoraish.mp3",
["107"] = "107.Al-Maun.mp3",
["108"] = "108.Al-Kawtar.mp3",
["109"] = "109.Al-Kafirun.mp3",
["110"] = "110.An-Nasr.mp3",
["111"] = "111.Al-Masad.mp3",
["112"] = "112.Al-Ihlas.mp3",
["113"] = "113.Al-Falaq.mp3",
["114"] = "114.An-Nas.mp3",
}
V25.items["SD"] = "Al-quran-with-sindhi-translation------high-quality-audio-mp3"
V25.files["SD"] = {
["1"] = "001 - Al-Fatihah ( The Opening ) - سورة الفاتحة.mp3",
["2"] = "002 - Al-Baqarah ( The Cow ) - سورة البقرة.mp3",
["3"] = "003 - Al-Imran ( The Family of Imran ) - سورة آل عمران.mp3",
["4"] = "004 - An-Nisa ( The Women ) - سورة النساء.mp3",
["5"] = "005 - Al-Maidah ( The Table spread with Food ) - سورة المائدة.mp3",
["6"] = "006 - Al-An'am ( The Cattle ) - سورة الأنعام.mp3",
["7"] = "007 - Al-A'raf (The Heights ) - سورة الأعراف.mp3",
["8"] = "008 - Al-Anfal ( The Spoils of War ) - سورة الأنفال.mp3",
["9"] = "009 - At-Taubah ( The Repentance ) - سورة التوبة.mp3",
["10"] = "010 - Yunus ( Jonah ) - سورة يونس.mp3",
["11"] = "011 - Hud - سورة هود.mp3",
["12"] = "012 - Yusuf (Joseph ) - سورة يوسف.mp3",
["13"] = "013 - Ar-Ra'd ( The Thunder ) - سورة الرعد.mp3",
["14"] = "014 - Ibrahim ( Abraham ) - سورة إبراهيم.mp3",
["15"] = "015 - Al-Hijr ( The Rocky Tract ) - سورة الحجر.mp3",
["16"] = "016 - An-Nahl ( The Bees ) - سورة النحل.mp3",
["17"] = "017 - Al-Isra ( The Night Journey ) - سورة الإسراء.mp3",
["18"] = "018 - Al-Kahf ( The Cave ) - سورة الكهف.mp3",
["19"] = "019 - Maryam ( Mary ) - سورة مريم.mp3",
["20"] = "020 - Taha - سورة طه.mp3",
["21"] = "021 - Al-Anbiya ( The Prophets ) - سورة الأنبياء.mp3",
["22"] = "022 - Al-Hajj ( The Pilgrimage ) - سورة الحج.mp3",
["23"] = "023 - Al-Mu'minoon ( The Believers ) - سورة المؤمنون.mp3",
["24"] = "024 - An-Noor ( The Light ) - سورة النور.mp3",
["25"] = "025 - Al-Furqan (The Criterion ) - سورة الفرقان.mp3",
["26"] = "026 - Ash-Shuara ( The Poets ) - سورة الشعراء.mp3",
["27"] = "027 - An-Naml (The Ants ) - سورة النمل.mp3",
["28"] = "028 - Al-Qasas ( The Stories ) - سورة القصص.mp3",
["29"] = "029 - Al-Ankaboot ( The Spider ) - سورة العنكبوت.mp3",
["30"] = "030 - Ar-Room ( The Romans ) - سورة الروم.mp3",
["31"] = "031 - Luqman - سورة لقمان.mp3",
["32"] = "032 - As-Sajdah ( The Prostration ) - سورة السجدة.mp3",
["33"] = "033 - Al-Ahzab ( The Combined Forces ) - سورة الأحزاب.mp3",
["34"] = "034 - Saba ( Sheba ) - سورة سبأ.mp3",
["35"] = "035 - Fatir ( The Orignator ) - سورة فاطر.mp3",
["36"] = "036 - Ya-seen - سورة يس.mp3",
["37"] = "037 - As-Saaffat ( Those Ranges in Ranks ) - سورة الصافات.mp3",
["38"] = "038 - Sad ( The Letter Sad ) - سورة ص.mp3",
["39"] = "039 - Az-Zumar ( The Groups ) - سورة الزمر.mp3",
["40"] = "040 - Ghafir ( The Forgiver God ) - سورة غافر.mp3",
["41"] = "041 - Fussilat ( Explained in Detail ) - سورة فصلت.mp3",
["42"] = "042 - Ash-Shura (Consultation ) - سورة الشورى.mp3",
["43"] = "043 - Az-Zukhruf ( The Gold Adornment ) - سورة الزخرف.mp3",
["44"] = "044 - Ad-Dukhan ( The Smoke ) - سورة الدخان.mp3",
["45"] = "045 - Al-Jathiya ( Crouching ) - سورة الجاثية.mp3",
["46"] = "046 - Al-Ahqaf ( The Curved Sand-hills ) - سورة الأحقاف.mp3",
["47"] = "047 - Muhammad - سورة محمد.mp3",
["48"] = "048 - Al-Fath ( The Victory ) - سورة الفتح.mp3",
["49"] = "049 - Al-Hujurat ( The Dwellings ) - سورة الحجرات.mp3",
["50"] = "050 - Qaf ( The Letter Qaf ) - سورة ق.mp3",
["51"] = "051 - Adh-Dhariyat ( The Wind that Scatter ) - سورة الذاريات.mp3",
["52"] = "052 - At-Tur ( The Mount ) - سورة الطور.mp3",
["53"] = "053 - An-Najm ( The Star ) - سورة النجم.mp3",
["54"] = "054 - Al-Qamar ( The Moon ) - سورة القمر.mp3",
["55"] = "055 - Ar-Rahman ( The Most Graciouse ) - سورة الرحمن.mp3",
["56"] = "056 - Al-Waqi'ah ( The Event ) - سورة الواقعة.mp3",
["57"] = "057 - Al-Hadid ( The Iron ) - سورة الحديد.mp3",
["58"] = "058 - Al-Mujadilah ( She That Disputeth ) - سورة المجادلة.mp3",
["59"] = "059 - Al-Hashr ( The Gathering ) - سورة الحشر.mp3",
["60"] = "060 - Al-Mumtahanah ( The Woman to be examined ) - سورة الممتحنة.mp3",
["61"] = "061 - As-Saff ( The Row ) - سورة الصف.mp3",
["62"] = "062 - Al-Jumu'ah ( Friday ) - سورة الجمعة.mp3",
["63"] = "063 - Al-Munafiqoon ( The Hypocrites ) - سورة المنافقون.mp3",
["64"] = "064 - At-Taghabun ( Mutual Loss & Gain ) - سورة التغابن.mp3",
["65"] = "065 - At-Talaq ( The Divorce ) - سورة الطلاق.mp3",
["66"] = "066 - At-Tahrim ( The Prohibition ) - سورة التحريم.mp3",
["67"] = "067 - Al-Mulk ( Dominion ) - سورة الملك.mp3",
["68"] = "068 - Al-Qalam ( The Pen ) - سورة القلم.mp3",
["69"] = "069 - Al-Haaqqah ( The Inevitable ) - سورة الحاقة.mp3",
["70"] = "070 - Al-Ma'arij (The Ways of Ascent ) - سورة المعارج.mp3",
["71"] = "071 - Nooh - سورة نوح.mp3",
["72"] = "072 - Al-Jinn ( The Jinn ) - سورة الجن.mp3",
["73"] = "073 - Al-Muzzammil (The One wrapped in Garments) - سورة المزمل.mp3",
["74"] = "074 - Al-Muddaththir ( The One Enveloped ) - سورة المدثر.mp3",
["75"] = "075 - Al-Qiyamah ( The Resurrection ) - سورة القيامة.mp3",
["76"] = "076 - Al-Insan ( Man ) - سورة الإنسان.mp3",
["77"] = "077 - Al-Mursalat ( Those sent forth ) - سورة المرسلات.mp3",
["78"] = "078 - An-Naba' ( The Great News ) - سورة النبأ.mp3",
["79"] = "079 - An-Nazi'at ( Those who Pull Out ) - سورة النازعات.mp3",
["80"] = "080 - Abasa ( He frowned ) - سورة عبس.mp3",
["81"] = "081 - At-Takwir ( The Overthrowing ) - سورة التكوير.mp3",
["82"] = "082 - Al-Infitar ( The Cleaving ) - سورة الانفطار.mp3",
["83"] = "083 - Al-Mutaffifin (Those Who Deal in Fraud) - سورة المطففين.mp3",
["84"] = "084 - Al-Inshiqaq (The Splitting Asunder) - سورة الانشقاق.mp3",
["85"] = "085 - Al-Burooj ( The Big Stars ) - سورة البروج.mp3",
["86"] = "086 - At-Tariq ( The Night-Comer ) - سورة الطارق.mp3",
["87"] = "087 - Al-A'la ( The Most High ) - سورة الأعلى.mp3",
["88"] = "088 - Al-Ghashiya ( The Overwhelming ) - سورة الغاشية.mp3",
["89"] = "089 - Al-Fajr ( The Dawn ) - سورة الفجر.mp3",
["90"] = "090 - Al-Balad ( The City ) - سورة البلد.mp3",
["91"] = "091 - Ash-Shams ( The Sun ) - سورة الشمس.mp3",
["92"] = "092 - Al-Layl ( The Night ) - سورة الليل.mp3",
["93"] = "093 - Ad-Dhuha ( The Forenoon ) - سورة الضحى.mp3",
["94"] = "094 - As-Sharh ( The Opening Forth) - سورة الشرح.mp3",
["95"] = "095 - At-Tin ( The Fig ) - سورة التين.mp3",
["96"] = "096 - Al-'alaq ( The Clot ) - سورة العلق.mp3",
["97"] = "097 - Al-Qadr ( The Night of Decree ) - سورة القدر.mp3",
["98"] = "098 - Al-Bayyinah ( The Clear Evidence ) - سورة البينة.mp3",
["99"] = "099 - Az-Zalzalah ( The Earthquake ) - سورة الزلزلة.mp3",
["100"] = "100 - Al-'adiyat ( Those That Run ) - سورة العاديات.mp3",
["101"] = "101 - Al-Qari'ah ( The Striking Hour ) - سورة القارعة.mp3",
["102"] = "102 - At-Takathur ( The piling Up ) - سورة التكاثر.mp3",
["103"] = "103 - Al-Asr ( The Time ) - سورة العصر.mp3",
["104"] = "104 - Al-Humazah ( The Slanderer ) - سورة الهمزة.mp3",
["105"] = "105 - Al-Fil ( The Elephant ) - سورة الفيل.mp3",
["106"] = "106 - Quraish - سورة قريش.mp3",
["107"] = "107 - Al-Ma'un ( Small Kindnesses ) - سورة الماعون.mp3",
["108"] = "108 - Al-Kauthor ( A River in Paradise) - سورة الكوثر.mp3",
["109"] = "109 - Al-Kafiroon ( The Disbelievers ) - سورة الكافرون.mp3",
["110"] = "110 - An-Nasr ( The Help ) - سورة النصر.mp3",
["111"] = "111 - Al-Masad ( The Palm Fibre ) - سورة المسد.mp3",
["112"] = "112 - Al-Ikhlas ( Sincerity ) - سورة الإخلاص.mp3",
["113"] = "113 - Al-Falaq ( The Daybreak ) - سورة الفلق.mp3",
["114"] = "114 - An-Nas ( Mankind ) - سورة الناس.mp3",
}
V25.items["PS"] = "AlQuranWithPushtoTranslationMisharyBinRashidAlafasyCD"
V25.files["PS"] = {
["1"] = "01 Al Fatiha.mp3",
["2"] = "02 Al Baqara.mp3",
["3"] = "03 Ale Imran.mp3",
["4"] = "04 An Nisa.mp3",
["5"] = "05 Al Maeda.mp3",
["6"] = "06 Al Anaam.mp3",
["7"] = "07 Al Aaraf.mp3",
["8"] = "08 Al Anfaal.mp3",
["9"] = "09 Al Tauba.mp3",
["10"] = "10 Younus.mp3",
["11"] = "11 Hood.mp3",
["12"] = "12 Yousuf.mp3",
["13"] = "13 Al Raad.mp3",
["14"] = "14 Ibrahim.mp3",
["15"] = "15 Al Hijr.mp3",
["16"] = "16 Al Nahal.mp3",
["17"] = "17 Al-Isra.mp3",
["18"] = "18 Al Kahf.mp3",
["19"] = "19 Mariyam.mp3",
["20"] = "20 Taha.mp3",
["21"] = "21 Al Ambia.mp3",
["22"] = "22 Al Hajj.mp3",
["23"] = "23 Al Mouminoon.mp3",
["24"] = "24 Al Noor.mp3",
["25"] = "25 Al Furqaan.mp3",
["26"] = "26 Al Shuara.mp3",
["27"] = "27 Al Naml.mp3",
["28"] = "28 Al Qasas.mp3",
["29"] = "29 Al Ankaboot.mp3",
["30"] = "30 Al Room.mp3",
["31"] = "31 Luqman.mp3",
["32"] = "32 Al Sajdah.mp3",
["33"] = "33 Al Ahzab.mp3",
["34"] = "34 Saba.mp3",
["35"] = "35 Faatir.mp3",
["36"] = "36 Yaseen.mp3",
["37"] = "37 Al Safaat.mp3",
["38"] = "38 Suaad.mp3",
["39"] = "39 Al Zumr.mp3",
["40"] = "40 Al-Ghafir.mp3",
["41"] = "41 Fussilat.mp3",
["42"] = "42 Al Shoorah.mp3",
["43"] = "43 Al Zukhraf.mp3",
["44"] = "44 Al Dukhan.mp3",
["45"] = "45 Al Jasiya.mp3",
["46"] = "46 Al Ahqaaf.mp3",
["47"] = "47 Muhammad.mp3",
["48"] = "48 Al Fatha.mp3",
["49"] = "49 Al Hujraat.mp3",
["50"] = "50 Qaaf.mp3",
["51"] = "51 Al Zarriyaat.mp3",
["52"] = "52 Al Toor.mp3",
["53"] = "53 Al Najam.mp3",
["54"] = "54 Al Qamar.mp3",
["55"] = "55 Al Rehman.mp3",
["56"] = "56 Al Waqiya.mp3",
["57"] = "57 Al Hadeed.mp3",
["58"] = "58 Al Mujadlah.mp3",
["59"] = "59 Al Hashar.mp3",
["60"] = "60 Al Mumtinah.mp3",
["61"] = "61 Al Saff.mp3",
["62"] = "62 Al Juma.mp3",
["63"] = "63 Al Munafiqoon.mp3",
["64"] = "64 Al Taghabun.mp3",
["65"] = "65 Al Talaaq.mp3",
["66"] = "66 Al Tahreem.mp3",
["67"] = "67 Al Mulk.mp3",
["68"] = "68 Al Qalam.mp3",
["69"] = "69 Al Haqqah.mp3",
["70"] = "70 Al Muarij.mp3",
["71"] = "71 Nuh.mp3",
["72"] = "72 Al Jinn.mp3",
["73"] = "73 Al Muzzamil.mp3",
["74"] = "74 Al Muddasir.mp3",
["75"] = "75 Al Qiyyamah.mp3",
["76"] = "76 Al-Insan.mp3",
["77"] = "77 Al Mursalat.mp3",
["78"] = "78 Al Naba.mp3",
["79"] = "79 Al Naziaat.mp3",
["80"] = "80 Al Abas.mp3",
["81"] = "81 Al Takwir.mp3",
["82"] = "82 Al Infitar.mp3",
["83"] = "83 Al Mutafafin.mp3",
["84"] = "84 Al Inshiqaq.mp3",
["85"] = "85 Al Buruj.mp3",
["86"] = "86 Al Tariq.mp3",
["87"] = "87 Al Aala.mp3",
["88"] = "88 Al Ghashiyah.mp3",
["89"] = "89 Al Fajar.mp3",
["90"] = "90 Al Balad.mp3",
["91"] = "91 Al Shams.mp3",
["92"] = "92 Al Lail.mp3",
["93"] = "93 Al Duha.mp3",
["94"] = "94 Ash-Sharh.mp3",
["95"] = "95 Al Teen.mp3",
["96"] = "96 Al Alaq.mp3",
["97"] = "97 Al Qadar.mp3",
["98"] = "98 Al Bayyinah.mp3",
["99"] = "99 Al Zilzal.mp3",
["100"] = "100 Al Aadiat.mp3",
["101"] = "101 Al Qariyah.mp3",
["102"] = "102 Al Takasur.mp3",
["103"] = "103 Al Aasar.mp3",
["104"] = "104 Al Humzah.mp3",
["105"] = "105 Al Feel.mp3",
["106"] = "106 Al Quraish.mp3",
["107"] = "107 Al Maoon.mp3",
["108"] = "108 Al Kausar.mp3",
["109"] = "109 Al kafirun.mp3",
["110"] = "110 Al Nasar.mp3",
["111"] = "111 Al Lahab.mp3",
["112"] = "112 Al Ikhlas.mp3",
["113"] = "113 Al Falaq.mp3",
["114"] = "114 Al Naas.mp3",
}
V25.items["FA"] = "QuranFarsiTranslation"
V25.files["FA"] = {
["1"] = "001-alFatiha.mp3",
["2"] = "002-alBaqara01.mp3",
["3"] = "003-alImran01.mp3",
["4"] = "004-anNisa01.mp3",
["5"] = "005-alMaeda01.mp3",
["6"] = "006-alAnam01.mp3",
["7"] = "007-alAraf01.mp3",
["8"] = "008-AlAnfal01.mp3",
["9"] = "009-alTawba01.mp3",
["10"] = "010-yunus01.mp3",
["11"] = "011-hud01.mp3",
["12"] = "012-yusuf01.mp3",
["13"] = "013-alRad.mp3",
["14"] = "014-Ibrahim.mp3",
["15"] = "015-alHijr.mp3",
["16"] = "016-alNahal01.mp3",
["17"] = "017-baniIsrail01.mp3",
["18"] = "018-alKahaf01.mp3",
["19"] = "019-Mariyum.mp3",
["20"] = "020-Taha01.mp3",
["21"] = "021-alAnbia01.mp3",
["22"] = "022-alHajj01.mp3",
["23"] = "023-alMouminoon01.mp3",
["24"] = "024-alNoor01.mp3",
["25"] = "025-alFurqan.mp3",
["26"] = "026-alShaura01.mp3",
["27"] = "027-alNamal01.mp3",
["28"] = "028-alQasas.mp3",
["29"] = "029-alAnkaboor01.mp3",
["30"] = "030-alRoom.mp3",
["31"] = "031-LUQMAN.mp3",
["32"] = "032-alSajdha.mp3",
["33"] = "033-alAhzab01.mp3",
["34"] = "034-Saba.mp3",
["35"] = "035-Fatir.mp3",
["36"] = "036-Yaseen.mp3",
["37"] = "037-AsSafaat.mp3",
["38"] = "038-Suaad.mp3",
["39"] = "039-azZumr01.mp3",
["40"] = "040-AlMumin.mp3",
["41"] = "041-hameemAlSajdha.mp3",
["42"] = "042-AlShoorah.mp3",
["43"] = "043-alZukhruf01.mp3",
["44"] = "044-alDukhaan.mp3",
["45"] = "045-alJasiya.mp3",
["46"] = "046-alAhqaf.mp3",
["47"] = "047-MUHAMMAD.mp3",
["48"] = "048-alFatha01.mp3",
["49"] = "049-alHujrat.mp3",
["50"] = "050-QAAF.mp3",
["51"] = "051-azZariyat.mp3",
["52"] = "052-alToor.mp3",
["53"] = "053-alNajm.mp3",
["54"] = "054-alQamar.mp3",
["55"] = "055-alRehman.mp3",
["56"] = "056-alWaqiya.mp3",
["57"] = "057-alHadeed.mp3",
["58"] = "058-alMujaadlah.mp3",
["59"] = "059-alHashr.mp3",
["60"] = "060-alMumtahina.mp3",
["61"] = "061-alSaff.mp3",
["62"] = "062-alJumma.mp3",
["63"] = "063-alMunafoqoon.mp3",
["64"] = "064-alTaghabun.mp3",
["65"] = "065-alTalaq.mp3",
["66"] = "066-alTahreem.mp3",
["67"] = "067-alMulk.mp3",
["68"] = "068-alQalm.mp3",
["69"] = "069-alHaqqah.mp3",
["70"] = "070-alMaurij.mp3",
["71"] = "071-Nuh.mp3",
["72"] = "072-alJin.mp3",
["73"] = "073-alMuzamil.mp3",
["74"] = "074-alMudasir.mp3",
["75"] = "075-alQiyamah.mp3",
["76"] = "076-alDuhar.mp3",
["77"] = "077-AlMursilat.mp3",
["78"] = "078-anNaba.mp3",
["79"] = "079-alNaziaat.mp3",
["80"] = "080-ABASA.mp3",
["81"] = "081-alTakwir.mp3",
["82"] = "082-alInfitar.mp3",
["83"] = "083-alMutafafin.mp3",
["84"] = "084-alInshiqaq.mp3",
["85"] = "085-alBuruj.mp3",
["86"] = "086-alTariq.mp3",
["87"] = "087-AlAala.mp3",
["88"] = "088-alGhashiyah.mp3",
["89"] = "089-alFajr.mp3",
["90"] = "090-alBalad.mp3",
["91"] = "091-alShams.mp3",
["92"] = "092-alLail.mp3",
["93"] = "093-alDuha.mp3",
["94"] = "094-alamNashrah.mp3",
["95"] = "095-AlTeen.mp3",
["96"] = "096-alAlaq.mp3",
["97"] = "097-alQadar.mp3",
["98"] = "098-alBayyinah.mp3",
["99"] = "099-alZizal.mp3",
["100"] = "100-alAadiat.mp3",
["101"] = "101-alQariyah.mp3",
["102"] = "102-AlTakasur.mp3",
["103"] = "103-alAsar.mp3",
["104"] = "104-alHumazah.mp3",
["105"] = "105-AlFeel.mp3",
["106"] = "106-QURAISH.mp3",
["107"] = "107-alMaoon.mp3",
["108"] = "108-alKausar.mp3",
["109"] = "109-alKafiroon.mp3",
["110"] = "110-AlNasar.mp3",
["111"] = "111-alLahab.mp3",
["112"] = "112-AlIkhlas.mp3",
["113"] = "113-alFalaq.mp3",
["114"] = "114-AlNaas.mp3",
}
V25.qariItems["waheed"] = "AlQuranWithUrduTranslationRecitationByQariWaheedZafarQasmiTranslationByMaulanaFatehMuhammadJalandhry"
V25.qariFiles["waheed"] = {
["1"] = "001-Surah_Al-Fatiha.mp3",
["2"] = "002-Surah_Al-Baqarah.mp3",
["3"] = "003-Surah_Aal-Imran.mp3",
["4"] = "004-Surah_An-Nissa.mp3",
["5"] = "005-Surah_Al-Maidah.mp3",
["6"] = "006-Surah_Al-An'am.mp3",
["7"] = "007-Surah_Al-A'raf.mp3",
["8"] = "008-Surah_Al-Anfal.mp3",
["9"] = "009-Surah_At-Tawba.mp3",
["10"] = "010-Surah_Yunus.mp3",
["11"] = "011-Surah_Hud.mp3",
["12"] = "012-Surah_Yusuf.mp3",
["13"] = "013-Surah_Ar-Ra'd.mp3",
["14"] = "014-Surah_Ibrahim.mp3",
["15"] = "015-Surah_Al-Hijr.mp3",
["16"] = "016-Surah_Al-Nahl.mp3",
["17"] = "017-Surah_Al-Israa.mp3",
["18"] = "018-Surah_Al-Kahf.mp3",
["19"] = "019-Surah_Marium.mp3",
["20"] = "020-Surah_Ta-ha.mp3",
["21"] = "021-Surah_Al-Anbiyaa.mp3",
["22"] = "022-Surah_Al-Hajj.mp3",
["23"] = "023-Surah_Al-Muminun.mp3",
["24"] = "024-Surah_An-Nur.mp3",
["25"] = "025-Surah_Al-Furqan.mp3",
["26"] = "026-Surah_Ash-Shu'araa.mp3",
["27"] = "027-Surah_An-Naml.mp3",
["28"] = "028-Surah_Al-Qasas.mp3",
["29"] = "029-Surah_Al-'Ankabut.mp3",
["30"] = "030-Surah_Ar-Rum.mp3",
["31"] = "031-Surah_Luqman.mp3",
["32"] = "032-Surah_As-Sajda.mp3",
["33"] = "033-Surah_Al-Ahzab.mp3",
["34"] = "034-Surah_Saba.mp3",
["35"] = "035-Surah_Fatir.mp3",
["36"] = "036-Surah_Yaseen.mp3",
["37"] = "037-Surah_As-Saffat.mp3",
["38"] = "038-Surah_Su'aad.mp3",
["39"] = "039-Surah_Az_Zumar.mp3",
["40"] = "040-Surah_Momin.mp3",
["41"] = "041-Surah_HamimSajda.mp3",
["42"] = "042-Surah_Ash_Shura.mp3",
["43"] = "043-Surah_Az_Zukhruf.mp3",
["44"] = "044-Surah_Ad_Dukhan.mp3",
["45"] = "045-Surah_Al_Jathiya.mp3",
["46"] = "046-Surah_Al_Ahqaf.mp3",
["47"] = "047-Surah_Muhammad.mp3",
["48"] = "048-Surah_Al_Fath.mp3",
["49"] = "049-Surah_Al_Hujurat.mp3",
["50"] = "050-Surah_Qaf.mp3",
["51"] = "051-Surah_Az_Zariyat.mp3",
["52"] = "052-Surah_At_Tur.mp3",
["53"] = "053-Surah_An_Najm.mp3",
["54"] = "054-Surah_Al_Qamar.mp3",
["55"] = "055-Surah_Ar_Rahman.mp3",
["56"] = "056-Surah_Al_Waqi'a.mp3",
["57"] = "057-Surah_Al_Hadid.mp3",
["58"] = "058-Surah_Al_Mujadila.mp3",
["59"] = "059-Surah_Al_Hashr.mp3",
["60"] = "060-Surah_Al_Mumtahana.mp3",
["61"] = "061-Surah_As_Saff.mp3",
["62"] = "062-Surah_Al_Jumu'a.mp3",
["63"] = "063-Surah_Al_Munafiqun.mp3",
["64"] = "064-Surah_At_Tagabun.mp3",
["65"] = "065-Surah_At_Talaq.mp3",
["66"] = "066-Surah_At_Tahrim.mp3",
["67"] = "067-Surah_Al_Mulk.mp3",
["68"] = "068-Surah_Al_Qalam.mp3",
["69"] = "069-Surah_Al_Haqqa.mp3",
["70"] = "070-Surah_Al_Ma'arij.mp3",
["71"] = "071-Surah_Nuh.mp3",
["72"] = "072-Surah_Al_Jinn.mp3",
["73"] = "073-Surah_Al_Muzzammil.mp3",
["74"] = "074-Surah_Al_Muddaththir.mp3",
["75"] = "075-Surah_Al_Qiyamat.mp3",
["76"] = "076-Surah_Al_Insan.mp3",
["77"] = "077-Surah_Al_Mursalat.mp3",
["78"] = "078-Surah_An_Nabaa.mp3",
["79"] = "079-Surah_An_Naziat.mp3",
["80"] = "080-Surah_Abasa.mp3",
["81"] = "081-Surah_At_Takwir.mp3",
["82"] = "082-Surah_Al_Infita.mp3",
["83"] = "083-Surah_Al_Mutaffifeen.mp3",
["84"] = "084-Surah_Al_Inshiqaq.mp3",
["85"] = "085-Surah_Al_Buruj.mp3",
["86"] = "086-Surah_At_Tariq.mp3",
["87"] = "087-Surah_Al_Ala.mp3",
["88"] = "088-Surah_Al_Gashiya.mp3",
["89"] = "089-Surah_Al_Fajr.mp3",
["90"] = "090-Surah_Al_Balad.mp3",
["91"] = "091-Surah_Ash_Shams.mp3",
["92"] = "092-Surah_Al_Lail.mp3",
["93"] = "093-Surah_Ad_Dhuha.mp3",
["94"] = "094-Surah_Al_Sharh.mp3",
["95"] = "095-Surah_At_Tin.mp3",
["96"] = "096-Surah_Al_Alaq.mp3",
["97"] = "097-Surah_Al_Qadr.mp3",
["98"] = "098-Surah_Al_Baiyina.mp3",
["99"] = "099-Surah_Al_Zalzalah.mp3",
["100"] = "100-Surah_Al_Adiyat.mp3",
["101"] = "101-Surah_Al_Qaria.mp3",
["102"] = "102-Surah_At_Takathur.mp3",
["103"] = "103-Surah_Al_Asr.mp3",
["104"] = "104-Surah_Al_Humaza.mp3",
["105"] = "105-Surah_Al_Fil.mp3",
["106"] = "106-Surah_Quraish.mp3",
["107"] = "107-Surah_Al_Maun.mp3",
["108"] = "108-Surah_Al_Kauthar.mp3",
["109"] = "109-Surah_Al_Kafirun.mp3",
["110"] = "110-Surah_An_Nasr.mp3",
["111"] = "111-Surah_Al_Masad.mp3",
["112"] = "112-Surah_Al_Ikhlas.mp3",
["113"] = "113-Surah_Al_Falaq.mp3",
["114"] = "114-Surah_An_Nas.mp3",
}
V25.qariItems["shakir"] = "QuranByQariShakirQasmi"
V25.qariFiles["shakir"] = {
["1"] = "Surah001Al-fateha-TheOpening.mp3",
["2"] = "Surah002Al-baqarah-TheCow.mp3",
["3"] = "Surah003Aal-e-imran-TheFamilyOfImran.mp3",
["4"] = "Surah004An-nisa-Women.mp3",
["5"] = "Surah005Al-maedah-TheTableSpread.mp3",
["6"] = "Surah006Al-anaam-Livestock.mp3",
["7"] = "Surah007Al-aaraaf-TheHeights.mp3",
["8"] = "Surah008Al-anfal-SpoilsOfWar.mp3",
["9"] = "Surah009At-tawba-Repentance.mp3",
["10"] = "Surah010Yunus-Jonah.mp3",
["11"] = "Surah011Hood-Hud.mp3",
["12"] = "Surah012Yusuf-Joseph.mp3",
["13"] = "Surah013Ar-raad-TheThunder.mp3",
["14"] = "Surah014Ibrahim-Abraham.mp3",
["15"] = "Surah015Al-hijr-StoneLand.mp3",
["16"] = "Surah016An-nahl-TheBee.mp3",
["17"] = "Surah017BaniIsraeel-ChildrenOfIsrael.mp3",
["18"] = "Surah018Al-kahf-TheCave.mp3",
["19"] = "Surah019Maryam-Mary.mp3",
["20"] = "Surah020TaHa-TaHa.mp3",
["21"] = "Surah021Al-ambiya-TheProphets.mp3",
["22"] = "Surah022Al-hajj-ThePilgrimage.mp3",
["23"] = "Surah023Al-momenoon-TheBelievers.mp3",
["24"] = "Surah024An-noor-TheLight.mp3",
["25"] = "Surah025Al-furqan-TheCriterion.mp3",
["26"] = "Surah026Ash-shuara-ThePoets.mp3",
["27"] = "Surah027An-naml-TheAnt.mp3",
["28"] = "Surah028Al-qasas-TheStory.mp3",
["29"] = "Surah029Al-ankaboot-TheSpider.mp3",
["30"] = "Surah030Ar-room-TheRomans.mp3",
["31"] = "Surah031Luqman-Luqman.mp3",
["32"] = "Surah032As-sajda-TheProstration.mp3",
["33"] = "Surah033Al-ahzab-TheClans.mp3",
["34"] = "Surah034Saba-Sheba.mp3",
["35"] = "Surah035Fatir-TheOriginatorOfCreation.mp3",
["36"] = "Surah036YaSeen-YaSin.mp3",
["37"] = "Surah037As-saffaat-DrawnUpInRanks.mp3",
["38"] = "Surah038Saad-ArabicLettersaad.mp3",
["39"] = "Surah039Az-zumar-TheTroops.mp3",
["40"] = "Surah040Al-momin-TheBeliever.mp3",
["41"] = "Surah041Haameem-HaMim.mp3",
["42"] = "Surah042Ash-shoora-Consultation.mp3",
["43"] = "Surah043Az-zukhruf-OrnamentsOfGold.mp3",
["44"] = "Surah044Ad-dukhan-Smoke.mp3",
["45"] = "Surah045Al-jaseyah-Crouching.mp3",
["46"] = "Surah046Al-ahqaf-TheDunes.mp3",
["47"] = "Surah047Muhammad-Mohammed.mp3",
["48"] = "Surah048Al-fatah-Victory.mp3",
["49"] = "Surah049Al-hujurat-ThePrivateAppartments.mp3",
["50"] = "Surah050Qaaf-ArabicLetterqaaf.mp3",
["51"] = "Surah051Az-zariat-TheWinnowingWinds.mp3",
["52"] = "Surah052At-toor-TheMount.mp3",
["53"] = "Surah053An-najm-TheStar.mp3",
["54"] = "Surah054Al-qamar-TheMoon.mp3",
["55"] = "Surah055Ar-rahman-TheBeneficient.mp3",
["56"] = "Surah056Al-waqia-TheEvent.mp3",
["57"] = "Surah057Al-hadeed-TheIron.mp3",
["58"] = "Surah058Al-mujadila-SheThatDisputeth.mp3",
["59"] = "Surah059Al-hashr-Exile.mp3",
["60"] = "Surah060Al-mumtahina-ExaminingHer.mp3",
["61"] = "Surah061As-saf-TheRanks.mp3",
["62"] = "Surah062Jummah-TheCongregation.mp3",
["63"] = "Surah063Al-munafiqoon-TheHypocrites.mp3",
["64"] = "Surah064At-tagabun-MutualDisillusion.mp3",
["65"] = "Surah065At-talaq-Divorce.mp3",
["66"] = "Surah066At-tahreem-Prohibition.mp3",
["67"] = "Surah067Al-mulk-TheSovereignty.mp3",
["68"] = "Surah068Al-qalam-ThePen.mp3",
["69"] = "Surah069Al-haaqah-TheReality.mp3",
["70"] = "Surah070Al-maarij-TheAscendingStairways.mp3",
["71"] = "Surah071Nuh-Noah.mp3",
["72"] = "Surah072Al-jinn-TheJinn.mp3",
["73"] = "Surah073Al-muzammil-TheEnshroudedOne.mp3",
["74"] = "Surah074Al-muddassir-TheCloakedOne.mp3",
["75"] = "Surah075Al-qiyama-TheResurrection.mp3",
["76"] = "Surah076Al-insan-Man.mp3",
["77"] = "Surah077Al-mursalat-TheEmissaries.mp3",
["78"] = "Surah078An-naba-TheTidings.mp3",
["79"] = "Surah079An-naziat-ThoseWhoDragForth.mp3",
["80"] = "Surah080Abasa-HeFrowned.mp3",
["81"] = "Surah081At-takwir-TheOverthrowing.mp3",
["82"] = "Surah082Al-infitar-TheCleaving.mp3",
["83"] = "Surah083Al-mutaffifin-Defrauding.mp3",
["84"] = "Surah084Al-inshiqaq-TheSundering.mp3",
["85"] = "Surah085Al-burooj-TheMansionsOfTheStars.mp3",
["86"] = "Surah086At-tariq-TheMorningStar1.mp3",
["87"] = "Surah087Al-ala-TheMostHigh.mp3",
["88"] = "Surah088Al-ghashiya-TheOverwhelming.mp3",
["89"] = "Surah089Al-fajr-TheDawn.mp3",
["90"] = "Surah090Al-balad-TheCity.mp3",
["91"] = "Surah091Ash-shams-TheSun.mp3",
["92"] = "Surah092Al-lail-TheNight.mp3",
["93"] = "Surah093Ad-dhuha-TheMorningHours.mp3",
["94"] = "Surah094AlmNashra-Solace.mp3",
["95"] = "Surah095At-tin-TheFig.mp3",
["96"] = "Surah096Al-alaq-TheClot.mp3",
["97"] = "Surah097Al-qadr-Power.mp3",
["98"] = "Surah098Al-bayyina-TheClearProof.mp3",
["99"] = "Surah099Az-zalzala-TheEarthquake.mp3",
["100"] = "Surah100Al-adiyat-TheCoursers.mp3",
["101"] = "Surah101Al-qaria-TheCalamity.mp3",
["102"] = "Surah102At-takathur-Competition.mp3",
["103"] = "Surah103Al-asr-TheDecliningDay.mp3",
["104"] = "Surah104Al-humaza-TheTraducer.mp3",
["105"] = "Surah105Al-fil-TheElephant.mp3",
["106"] = "Surah106Quraish-Quraysh.mp3",
["107"] = "Surah107Al-maun-SmallKindnesses.mp3",
["108"] = "Surah108Al-kauther-Abundance.mp3",
["109"] = "Surah109Al-kafiroon-TheDisbelievers.mp3",
["110"] = "Surah110An-nasr-DivineSupport.mp3",
["111"] = "Surah111Al-masadd-TheFlame.mp3",
["112"] = "Surah112Al-ikhlas-TheUnityOfGod.mp3",
["113"] = "Surah113Al-falaq-TheDaybreak.mp3",
["114"] = "Surah114An-nas-Mankind.mp3",
}
V25.modes = { ["English"] = {kind="translation", key="EN", label="English (Ibrahim Walk)"}, ["English (Mishary)"] = {kind="translation", key="EN2", label="English (Mishary)"}, ["Hindi"] = {kind="translation", key="HI", label="Hindi"}, ["Bengali"] = {kind="translation", key="BN", label="Bengali"}, ["French"] = {kind="translation", key="FR", label="French"}, ["Sindhi"] = {kind="translation", key="SD", label="Sindhi"}, ["Pashto"] = {kind="translation", key="PS", label="Pashto"}, ["Farsi"] = {kind="translation", key="FA", label="Farsi"}, ["Urdu (Waheed Zafar)"] = {kind="qari", key="waheed", label="Urdu Audio - Whole Surah (Waheed Zafar)"}, ["Urdu (Shakir Qasmi)"] = {kind="qari", key="shakir", label="Urdu Whole-Surah (Shakir Qasmi)"}, }
local function v25UrlEncodeBytes(str)
return (str:gsub("[^%w%-%.%_%~]", function(c) return string.format("%%%02X", string.byte(c)) end))
end
M.buildV25WholeTrack = function(mode, surahIdx)
local cfg = V25.modes[mode]
if not cfg or surahIdx < 1 or surahIdx > 114 then return nil, nil end
local files, item
if cfg.kind == "qari" then
files, item = V25.qariFiles[cfg.key], V25.qariItems[cfg.key]
else
files, item = V25.files[cfg.key], V25.items[cfg.key]
end
local fn = files and files[tostring(surahIdx)]
if not fn or not item then return nil, nil end
local url = "https://archive.org/download/" .. item .. "/" .. v25UrlEncodeBytes(fn)
local pathName = "v27_" .. cfg.key .. "_surah_" .. string.format("%03d", surahIdx) .. ".mp3"
return url, pathName
end
local V25_TRANSLATION_LABELS = { "Off", "Urdu", "Hindi", "Punjabi", "English", "Sindhi", "English (Mishary)", "Bengali", "French", "Pashto", "Farsi", "Urdu (Waheed Zafar)", "Urdu (Shakir Qasmi)" }
function V25.mkQFiles(suf, pre)
local t = {}
for i = 1, 114 do t[tostring(i)] = (pre or "") .. string.format("%03d", i) .. suf end
return t
end
function V25.mkUSufFiles(us, tail)
local t, i = {}, 0
for sfx in us:gmatch("[^|]+") do i = i + 1 t[tostring(i)] = string.format("%03d", i) .. sfx .. (tail or ".mp3") end
return t
end
function V25.mkPFiles(pre)
local t = {}
for i = 1, 30 do t[tostring(i)] = string.format(pre, i) end
return t
end
V25_KZ="Fatiha|Baqarah|AlImran|Nisa|Maidah|Anaam|Araf|Anfal|Tauba|Yunus|Hood|Yousuf|Rad|Ibrahim|Hajar|Nahl|BaniIsrael|Kahf|Maryam|Taha|Anbiya|Hajj|Muminoon|Noor|Furqan|Shuara|Naml|Qasas|Ankaboot|Room|Luqman|Sajda|Ahzab|Saba|Fatir|Ya-seen|Saaffat|Sad|Zumar|Momin|HaMeemSajda|Shura|Zukhruf|Dukhan|Jasia|Ahqaf|Muhammad|Fatah|Hujurat|Qaf|Zariyat|Tur|Najam|Qamar|Rehman|Waqiah|Hadid|Mujadila|Hashr|Mumtahina|AsSaff|Jumua|Munafiqun|Taghabun|Talaq|Tahrim|Mulk|Qalam|Haqqa|Maarij|Nuh|Jinn|Muzzammil|Mudassir|Qiyamah|Dahr|Mursalat|Naba|Naziat|Abasa|Takwir|Infitar|Mutaffifin|Inshiqaq|Burooj|Tariq|Al-ala|Ghashiya|Fajr|Balad|Shams|Al-lail|Dhuha|Sharh|At-tin|Al-alaq|Qadr|Bayyinah|Zalzalah|Adiyat|Al-qariah|Takasur|Al-asr|Humazah|Al-fil|Quraish|Al-maun|Kausar|Kafirun|Nasr|Lahab|Ikhlas|Falaq|Naas"
function V25.mkKZFiles()
local t={} local i=1
for x in string.gmatch(V25_KZ,"[^|]+") do t[tostring(i)]=string.format("%03d",i).."Surah"..x..".mp3" i=i+1 end
t["1"]="001 Surah Fatiha.mp3" return t end
local HUS = "-Al-Fatiha|-Al-Baqarah2|-Al-imran|-An-Nisa|-Al-Maidah|-Enam|-Al-Araf|-Al-Anfal|.At-Taubah|-Yunus|-Hud|-Yusuf|-Ar-Rad|-ibrahim|-Al-Hijr|-An-Nahl|-Al-Isra|-Al-Kahf|.Maryam|.Ta-Ha|-Al-Anbiya|-Al-Hajj|-Al-Mu-minun|-An-Nur|-Al-Furqan|-Ash-Shu-ara|-An-Naml|-Al-Qasas|-Al-Ankabut|-Ar-Rum|-Luqman|-As-Sajdah|-Al-Ahzab|-Saba.|-Fatir|-Ya-Sin|-As-Saffat|-Sad|-Az-Zumar|-Mumin-Ghafir|-Fussilat|-Ash-Shura|-Az-Zukhruf|-Ad-Dukhan|-Al-Jathiyah|-Al-Ahqaf|-Muhammad|-Al-Fath|-Al-Hujurat|-Qaf|-Adh-Dhariyat|-At-Tur|-An-Najm|-Al-Qamar|-Ar-Rahman|-Al-Waqi-ah|-Al-Hadid|-Al-Mujadilah|-Al-Hashr|-Al-Mumtahanah|-As-Saff|-Al-Jumu-ah|-Al-Munafiqun|-At-Taghabun|-At-Talaq|-At-Tahrim|-Al-Mulk|-Al-Qalam|-Al-Haqqah|-Al-Maarij|-Nuh|-Al-Jinn|-Al-Muzzammil|-Al-Muddaththir|-Al-Qiyamah|-Al-Insan|-Al-Mursalat|-Al-Naba|-Al-Naaze|-Abasa|-Al-Takweer|-Al-Infitaar|-Al-Mutaffifeen|-Al-Inshiqaaq|-Al-Burooj|-Al-Taareq|-Al-A-alaa|-Al-Ghaasheyah|-Al-Fajr|-Al-Balad|-Al-Shams|-Al-Layl|-Al-Duhaa|-Al-insirah|-Al-Teen|-Al-Alaq|-Al-Qadr|-Al-Bayyinah|-Al-Zilzalaha|-Al-Aadeyat|-Al-Qaare-ah|-Al-Takasur|-Al-Asr|-Al-Humazah|-Al-Feel|-Al-Quraishinsirah|-Al-Maa-oon|-Al-Kausar|-Al-Kaaferoon|-Al-Nasr|-Al-Masad|-Al-Ikhlaas|-Al-Falaq|-Al-Naas"
local IRS = ".Al-fatihah|.Al-baqarah|.Aal-e-imran|.An-nisa|.Al-maidah|.Al-anam|.Al-araf|.Al-anfal|.At-taubah|.Yunus|.Hud|.Yusuf|.Ar-rad|.Ibrahim|.Al-hijr|.An-nahl|.Al-isra|.Al-kahf|.Maryam|.Ta-ha|.Al-anbiya|.Al-hajj|.Al-muminun|.An-nur|.Al-furqan|.Ash-shuara|.An-naml|.Al-qasas|.Al-ankabut|.Ar-rum|.Luqman|.As-sajdah|.Al-ahzab|.Saba|.Fatir|.Ya-sin|.As-saffat|.Sad|.Az-zumar|.Ghafir|.Fussilat|.Ash-shura|.Az-zukhruf|.Ad-dukhan|.Al-jathiya|.Al-ahqaf|.Muhammad|.Al-fath|.Al-hujurat|.Qaf|.Az-zariyat|.At-tur|.An-najm|.Al-qamar|.Ar-rahman|.Al-waqiah|.Al-hadid|.Al-mujadilah|.Al-hashr|.Al-mumtahinah|.As-saff|.Al-jumuah|.Al-munafiqun|.At-taghabun|.At-talaq|.At-tahrim|.Al-mulk|.Al-qalam|.Al-haqqah|.Al-maarij|.Nuh|.Al-jinn|.Al-muzzammil|.Al-muddaththir|.Al-qiyamah|.Al-insan|.Al-mursalat|.An-naba|.An-naziat|.abasa|.At-takwir|.Al-infitar|.Al-mutaffifin|.Al-inshiqaq|.Al-buruj|.At-tariq|.Al-ala|.Al-ghashiyah|.Al-fajr|.Al-balad|.Ash-shams|.Al-lail|.Ad-duha|.Ash-sharh|.At-tin|.Al-alaq|.Al-qadr|.Al-baiyinah|.Az-zalzalah|.Al-adiyat|.Al-qariah|.At-takathur|.Al-asr|.Al-humazah|.Al-fil|.Quraish|.Al-maun|.Al-kauthar|.Al-kafirun|.An-nasr|.Al-masad|.Al-ikhlas|.Al-falaq|.An-nas"
local V25_URDU_NEW = {
 {k="u1", i="SheikhSudaisAndShuraimUrduTranslation", l="Urdu (Sudais & Shuraim)", suf="%20www.quranaudio.info.mp3"},
 {k="u2", i="AbdulBasitAbdulSamadQuranWithUrduTranslation", l="Urdu (Abdul Basit)", suf="%20www.quranaudio.info.mp3"},
 {k="u3", i="c3687113_trbvm_002", l="Urdu (Maher Al Muaiqly)", suf=".mp3"},
 {k="u4", i="BeautifulAudioQuranRecitationWithUrduTranslation", l="Urdu (Abdullah Momin)", suf=".mp3"},
 {k="u5", i="Saud_al-shuraim_with_abdulrahman_alsudaesurduTranslation_mp3_quran", l="Urdu (Saud Al Shuraim)", suf=".mp3"},
 {k="u6", i="MohammedSiddiqAl-MinshawiWithUrduTranslationDownload", l="Urdu (Minshawi)", suf=".mp3"},
 {k="u7", i="HANIAR-RIFAIWithUrduTranslationQuran", l="Urdu (Hani Al Rifai)", suf=".mp3"},
 {k="u8", i="audio-quran-with-urdu-translation", l="Urdu (Aasan Tarjuma - Taqi Usmani)", suf=".mp3", pre="tu_mr_s_"},
 {k="u9", i="quran_urdu_audio_only", l="Urdu (Sirf Tarjuma - Bagair Tilawat)", suf=".mp3"},
 {k="u10", i="Al_Quran_Ahmad_AlAjmy_with_Urdu_Translation", l="Urdu (Ahmed Al-Ajmi)", n={["1"]="01AL-FATIHAH.mp3",["2"]="02AL-BAQARAH.mp3",["3"]="03Al-imran.mp3",["4"]="04An-nisa.mp3",["5"]="05Al-maidah.mp3",["6"]="06Al-anam.mp3",["7"]="07Al-araf.mp3",["8"]="08Al-anfal.mp3",["9"]="09At-taubah.mp3",["10"]="10Yunus.mp3",["11"]="11Hood.mp3",["12"]="12Yusuf.mp3",["13"]="13Ar-rad.mp3",["14"]="14Ibrahim.mp3",["15"]="15Al-hijr.mp3",["16"]="16Al-nahl.mp3",["17"]="17Al-israa.mp3",["18"]="18Al-kahf.mp3",["19"]="19Maryam.mp3",["20"]="20Ta-ha.mp3",["21"]="21Al-anbiya.mp3",["22"]="22Al-hajj.mp3",["23"]="23Al-muminun.mp3",["24"]="24An-nur.mp3",["25"]="25Al-furqan.mp3",["26"]="26Ash-shuara.mp3",["27"]="27An-naml.mp3",["28"]="28Al-Qasas.mp3",["29"]="29Al-ankabut.mp3",["30"]="30Ar-room.mp3",["31"]="31Luqman.mp3",["32"]="32As-sajdah.mp3",["33"]="33Al-ahzab.mp3",["34"]="34Saba.mp3",["35"]="35Fatir.mp3",["36"]="36Ya-sin.mp3",["37"]="37As-saffat.mp3",["38"]="38Sad.mp3",["39"]="39Az-zumar.mp3",["40"]="40Ghafir.mp3",["41"]="41Fussilat.mp3",["42"]="42Ash-shura.mp3",["43"]="43Az-zukhruf.mp3",["44"]="44Ad-dukhan.mp3",["45"]="45Al-jathiya.mp3",["46"]="46Al-ahqaf.mp3",["47"]="47Muhammad.mp3",["48"]="48Al-fath.mp3",["49"]="49Al-hujurat.mp3",["50"]="50Qaf.mp3",["51"]="51Az-zariyat.mp3",["52"]="52At-tur.mp3",["53"]="53An-najm.mp3",["54"]="54Al-qamar.mp3",["55"]="55Ar-rahman.mp3",["56"]="56Al-waqiah.mp3",["57"]="57Al-hadid.mp3",["58"]="58Al-mujadila.mp3",["59"]="59Al-hashr.mp3",["60"]="60Al-mumtahinah.mp3",["61"]="61As-saff.mp3",["62"]="62Al-jumuah.mp3",["63"]="63Al-munafiqun.mp3",["64"]="64At-taghabun.mp3",["65"]="65At-talaq.mp3",["66"]="66At-tahrim.mp3",["67"]="67Al-mulk.mp3",["68"]="68Al-qalam.mp3",["69"]="69Al-haqqah.mp3",["70"]="70Al-maarij.mp3",["71"]="71Nooh.mp3",["72"]="72Al-jinn.mp3",["73"]="73Al-muzzammil.mp3",["74"]="74Al-muddaththir.mp3",["75"]="75Al-qiyamah.mp3",["76"]="76Al-insan.mp3",["77"]="77Al-mursalat.mp3",["78"]="78An-naba.mp3",["79"]="79An-naziat.mp3",["80"]="80abasa.mp3",["81"]="81At-takwir.mp3",["82"]="82Al-infitar.mp3",["83"]="83Al-mutaffifin.mp3",["84"]="84Al-inshiqaq.mp3",["85"]="85Al-buruj.mp3",["86"]="86At-tariq.mp3",["87"]="87Al-ala.mp3",["88"]="88Al-ghashiyah.mp3",["89"]="89Al-fajr.mp3",["90"]="90Al-balad.mp3",["91"]="91Ash-shams.mp3",["92"]="92Al-lail.mp3",["93"]="93Ad-duha.mp3",["94"]="94Ash-sharh.mp3",["95"]="95At-tin.mp3",["96"]="96Al-alaq.mp3",["97"]="97Al-qadr.mp3",["98"]="98Al-baiyinah.mp3",["99"]="99Az-zazalah.mp3",["100"]="_100Al-adiyat.mp3",["101"]="_101Al-qaria.mp3",["102"]="_102At-takathur.mp3",["103"]="_103Al-asr.mp3",["104"]="_104Al-humazah.mp3",["105"]="_105Al-fil.mp3",["106"]="_106Quraish.mp3",["107"]="_107Al-maun.mp3",["108"]="_108Al-kauthar.mp3",["109"]="_109Al-kafirun.mp3",["110"]="_110An-nasr.mp3",["111"]="_111Al-masad.mp3",["112"]="_112Al-ikhlas.mp3",["113"]="_113Al-falaq.mp3",["114"]="_114An-nas.mp3"}},
 {k="u11", i="AbdullahAliBasfarMp3QuranWithUrduTranslationfull-ogg", l="Urdu (Abdullah Ali Basfar)", suf=".mp3"},
 {k="u12", i="Urdu_Audio_Quran_Translation", l="Urdu (Tarjuma - Doosri Recording)", suf=".mp3"},
 {k="u13", i="TilawaatEQuranByMuhammadAsadAttariAndTarjumaEKanzUlImanByAbdulHabibAttari", l="Kanzul Iman - Attari", n=V25.mkKZFiles()},
 {k="t11", i="quran-juz-audio-mp3", l="Para-wise (Maher Al Muaiqly)", suf="Para %02d.mp3", lb="Urdu Para-wise (Maher Al Muaiqly, 30 Paras)"},
 {k="t12", i="Quran-e-Kareem-With-Urdu-Translation-Fateh-Muhammad-Jalandhari", l="Para-wise (Meeraj-ud-Din Khan)", suf="Al-Quran_Urdu_Parah-%02d.mp3", lb="Urdu Para-wise (Meeraj-ud-Din Khan, 30 Paras)"},
 {k="t1", i="HolyQuranEnglishTranslation", l="English (Poora Surah)", suf=".mp3", lb="English Tarjuma (Poora Surah)"},
 {k="t2", i="punjabiquranmp3", l="Punjabi (Poora Surah)", suf=".mp3", lb="Punjabi Tarjuma (Poora Surah)"},
 {k="t3", i="Chinese_Audio_Quran_Translation_uP_bY_mUSLEm", l="Chinese (Poora Surah)", suf=".mp3", lb="Chinese Tarjuma (Poora Surah)"},
 {k="t4", i="KORAN--recitation-recited--by-translation-to-chinese-without-arabic", l="Chinese (Sirf Tarjuma)", suf=".mp3", lb="Chinese Sirf Tarjuma (Bagair Tilawat)"},
 {k="t5", i="Al-Quran-with-Urdu-Translation-Audio-MP3", l="Urdu (Fateh Muhammad Jalandhari)", fn="hindi", lb="Urdu Tarjuma (Fateh Muhammad Jalandhari)"},
 {k="t6", i="Quran-e-Kareem-With-Urdu-ONLY-Translation-Fateh-Muhammad-Jalandhari-------Audio-MP3-CD", l="Urdu (Sirf Tarjuma - FMJ)", fn="hindi", lb="Urdu Sirf Tarjuma (FMJ Recording)"},
 {k="t7", i="hindi-meal", l="Hindi (Poora Surah 128k)", us=HUS, lb="Hindi Tarjuma (Poora Surah 128k)"},
 {k="t8", i="hindi-meal", l="Hindi (Poora Surah 64k)", us=HUS, tail="_64kb.mp3", lb="Hindi Tarjuma (Poora Surah 64k)"},
 {k="t9", i="Holy-Quran-Urdu-Translation/Sudais-and-Shuraim", l="Arabic (Sudais & Shuraim)", suf=".mp3", lb="Arabic Tilawat (Sudais & Shuraim)"},
 {k="t10", i="Irfan-ul-quranAudio", l="Urdu (Irfan-ul-Quran)", us=IRS, lb="Urdu Tarjuma (Irfan-ul-Quran - Kanzul Irfan)"},
}
for _, q in ipairs(V25_URDU_NEW) do
V25.qariItems[q.k] = q.i
V25.qariFiles[q.k] = q.n or (q.us and V25.mkUSufFiles(q.us, q.tail)) or (q.fn == "hindi" and M.hindiTranslationFiles()) or (q.suf and q.suf:find("%%02d") and V25.mkPFiles(q.suf)) or V25.mkQFiles(q.suf, q.pre)
V25.modes[q.l] = {kind="qari", key=q.k, label=q.lb or ("Urdu Tarjuma: " .. q.l .. " (poora surah)")}
table.insert(V25_TRANSLATION_LABELS, q.l)
end
local farsiVoice = prefs.getString("farsiAyahVoice", "Fooladvand")
M.saveFarsiVoice = function(v)
farsiVoice = v
prefs.edit().putString("farsiAyahVoice", v).apply()
end
M.buildFarsiAyahUrl = function(surahIdx, ayahNum)
local folder = (farsiVoice == "Makarem") and "Makarem_Kabiri_16Kbps" or "Fooladvand_Hedayatfar_40Kbps"
return "https://everyayah.com/data/translations/" .. folder .. "/" .. string.format("%03d%03d", surahIdx, ayahNum) .. ".mp3"
end
local ADHAN_ARCHIVE="https://archive.org/download/90---azan---90---azan--many----sound----mp3---alazan/"
local AZAN_TRACKS = { {name="Adhan 1 (Archive)", url=ADHAN_ARCHIVE.."001-.mp3"}, {name="Adhan 2 (Archive)", url=ADHAN_ARCHIVE.."002--.mp3"}, {name="Adhan 3 (Archive)", url=ADHAN_ARCHIVE.."003--.mp3"}, {name="Adhan 4 (Archive)", url=ADHAN_ARCHIVE.."004----1.mp3"}, {name="Adhan 5 (Archive)", url=ADHAN_ARCHIVE.."005----2.mp3"}, {name="Adhan 6 (Archive)", url=ADHAN_ARCHIVE.."006--.mp3"}, {name="Adhan 7 (Archive)", url=ADHAN_ARCHIVE.."007--.mp3"}, {name="Adhan 8 (Archive)", url=ADHAN_ARCHIVE.."008--.mp3"}, {name="Adhan 9 (Archive)", url=ADHAN_ARCHIVE.."009--.mp3"}, {name="Adhan 10 (Archive)", url=ADHAN_ARCHIVE.."010--.mp3"}, {name="Adhan Makkah (IslamCan)", url="https://www.islamcan.com/audio/adhan/azan3.mp3"}, {name="Adhan (IslamCan 4)", url="https://www.islamcan.com/audio/adhan/azan4.mp3"}, {name="Adhan (IslamCan 5)", url="https://www.islamcan.com/audio/adhan/azan5.mp3"}, {name="Adhan (IslamCan 7)", url="https://www.islamcan.com/audio/adhan/azan7.mp3"}, {name="Adhan (IslamCan 10)", url="https://www.islamcan.com/audio/adhan/azan10.mp3"}, }
M.getAzanLocalPath = function(i) return azanAudioDir .. "azan_" .. tostring(i) .. ".mp3" end
local translationMode = prefs.getString("translationMode", "Off")
if translationMode == "Chinese" then translationMode = "Off" end
if translationMode=="Waheed Zafar" or translationMode=="Urdu Audio - Whole Surah (Waheed Zafar)" or translationMode=="Urdu Whole-Surah (Waheed Zafar)" then translationMode="Urdu (Waheed Zafar)" end
if translationMode=="Shakir Qasmi" or translationMode=="Urdu Audio - Whole Surah (Shakir Qasmi)" or translationMode=="Urdu Whole-Surah (Shakir Qasmi)" then translationMode="Urdu (Shakir Qasmi)" end
prefs.edit().putString("translationMode",translationMode).apply()
M.saveTranslationMode = function(v)
translationMode = v
prefs.edit().putString("translationMode", v).apply()
end
local ayahAudioDir = duaAudioDir:gsub("Dua_Audio", "Ayah_Audio")
if not File(ayahAudioDir).exists() then File(ayahAudioDir).mkdirs() end
M.buildAyahUrl = function(surahIdx, ayahNum)
return "https://everyayah.com/data/Alafasy_128kbps/" .. string.format("%03d%03d", surahIdx, ayahNum) .. ".mp3"
end
M.getAyahAudioLocal = function(surahIdx, ayahNum)
return ayahAudioDir .. "s" .. surahIdx .. "_a" .. ayahNum .. ".mp3"
end
M.buildUrduAyahUrl = function(surahIdx, ayahNum)
return "https://everyayah.com/data/translations/urdu_shamshad_ali_khan_46kbps/" .. string.format("%03d%03d", surahIdx, ayahNum) .. ".mp3"
end
M.getUrduAyahAudioLocal = function(surahIdx, ayahNum)
return ayahAudioDir .. "urdu_s" .. surahIdx .. "_a" .. ayahNum .. ".mp3"
end
M.buildFarhatAyahUrl = function(surahIdx, ayahNum)

M.buildKanzulAyahUrl = function(surahIdx, ayahNum)
return "https://archive.org/download/kanzul-iman-urdu-audio-translation/" .. string.format("%03d%03d", surahIdx, ayahNum) .. ".mp3"
end
M.getKanzulAyahAudioLocal = function(surahIdx, ayahNum)
return (string.gsub(M.getFarhatAyahAudioLocal(surahIdx, ayahNum), "farhat", "kanzul"))
end
return "https://everyayah.com/data/translations/urdu_farhat_hashmi/" .. string.format("%03d%03d", surahIdx, ayahNum) .. ".mp3"
end
M.getFarhatAyahAudioLocal = function(surahIdx, ayahNum)
return ayahAudioDir .. "farhat_s" .. surahIdx .. "_a" .. ayahNum .. ".mp3"
end
local urduVoice = prefs.getString("urduVoice", "Shamshad")
M.saveUrduVoice = function(v)
urduVoice = v
prefs.edit().putString("urduVoice", v).apply()
end
M.currentUrduAyahPair = function(surahIdx, n)
if urduVoice == "Kanzul" then return M.buildKanzulAyahUrl(surahIdx, n), M.getKanzulAyahAudioLocal(surahIdx, n) end
if urduVoice == "Farhat" then
return M.buildFarhatAyahUrl(surahIdx, n), M.getFarhatAyahAudioLocal(surahIdx, n)
else
return M.buildUrduAyahUrl(surahIdx, n), M.getUrduAyahAudioLocal(surahIdx, n)
end
end
M.buildEnglishAyahUrl = function(surahIdx, ayahNum)
return "https://everyayah.com/data/English/Sahih_Intnl_Ibrahim_Walk_192kbps/" .. string.format("%03d%03d", surahIdx, ayahNum) .. ".mp3"
end
M.getEnglishAyahAudioLocal = function(surahIdx, ayahNum)
return ayahAudioDir .. "english_s" .. surahIdx .. "_a" .. ayahNum .. ".mp3"
end
M.getFarsiAyahAudioLocal = function(surahIdx, ayahNum)
return ayahAudioDir .. "farsi_" .. string.lower(farsiVoice) .. "_s" .. surahIdx .. "_a" .. ayahNum .. ".mp3"
end
M.makeByteBuffer = function(size)
local ok, buf = pcall(function() return byte[size] end)
if ok and buf then return buf end
local ok2, buf2 = pcall(function() return luajava.newArray("byte", size) end)
if ok2 and buf2 then return buf2 end
return nil
end
local lastDownloadError = ""
M.directDownload = function(urlStr, destPath)
local conn, inStream, outStream
local ok, err = pcall(function()
conn = URL(urlStr).openConnection()
conn.setConnectTimeout(10000)
conn.setReadTimeout(15000)
conn.setInstanceFollowRedirects(true)
inStream = conn.getInputStream()
outStream = FileOutputStream(destPath)
local usedUtil = pcall(function() LuaUtil.copyFile(inStream, outStream) end)
if not usedUtil then
local buffer = M.makeByteBuffer(4096)
if not buffer then error("byte buffer creation failed - no working array API found") end
local len = inStream.read(buffer)
while len and len > 0 do
outStream.write(buffer, 0, len)
len = inStream.read(buffer)
end
end
end)
pcall(function() if outStream then outStream:flush() end end)
pcall(function() if outStream then outStream:close() end end)
pcall(function() if inStream then inStream:close() end end)
pcall(function() if conn then conn:disconnect() end end)
if not ok then
lastDownloadError = tostring(err)
pcall(function() File(destPath).delete() end)
return false
end
local f = File(destPath)
if not f.exists() or f.length() < 1000 then
lastDownloadError = "file too small (" .. tostring(f.exists() and f.length() or 0) .. " bytes) - likely truncated"
pcall(function() f.delete() end)
return false
end
return true
end
M.downloadSequentially = function(items, index, doneCount, onProgress, onComplete)
if index > #items then
onComplete(doneCount)
return
end
local item = items[index]
Thread(Runnable{run=function()
pcall(function() Thread.currentThread():setPriority(Thread.MIN_PRIORITY) end)
local success = File(item.path).exists()
if not success then
success = M.directDownload(item.url, item.path)
end
local newDone = doneCount + (success and 1 or 0)
handler.postDelayed(function()
pcall(onProgress, newDone, index)
M.downloadSequentially(items, index + 1, newDone, onProgress, onComplete)
end, 40)
end}).start()
end
local paraNames = {}
for i=1,30 do paraNames[i] = "Para " .. i .. " (" .. surahNames[paraSurahStart[i]] .. " se)" end
local wazaifCategories = {"General Zikr", "Morning Azkar", "Evening Azkar", "Protection", "Durood Shareef"}
local wazaifLabels = { "Bismillah", "SubhanAllah", "Alhamdulillah", "Allahu Akbar", "La Ilaha Illallah", "Astaghfirullah", "SubhanAllahi Wa Bihamdihi", "Hasbunallahu Wa Ni'mal Wakeel", "La Hawla Wa La Quwwata", "Ayatul Kursi", "Durood-e-Ibrahimi" }
local wazaifArabicText = { "بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ", "سُبْحَانَ اللَّهِ", "الْحَمْدُ لِلَّهِ", "اللَّهُ أَكْبَرُ", "لَا إِلَٰهَ إِلَّا اللَّهُ", "أَسْتَغْفِرُ اللَّهَ", "سُبْحَانَ اللَّهِ وَبِحَمْدِهِ", "حَسْبُنَا اللَّهُ وَنِعْمَ الْوَكِيلُ", "لَا حَوْلَ وَلَا قُوَّةَ إِلَّا بِاللَّهِ", "اللَّهُ لَا إِلَٰهَ إِلَّا هُوَ الْحَيُّ الْقَيُّومُ", "اللَّهُمَّ صَلِّ عَلَى مُحَمَّدٍ وَعَلَى آلِ مُحَمَّدٍ" }
local dailyAyahs = { {ar="فَإِنَّ مَعَ الْعُسْرِ يُسْرًا", ur="پس بے شک مشکل کے ساتھ آسانی ہے", ref="Surah Ash-Sharh: 5"}, {ar="وَاسْتَعِينُوا بِالصَّبْرِ وَالصَّلَاةِ", ur="اور صبر اور نماز کے ذریعے مدد طلب کرو", ref="Surah Al-Baqarah: 45"}, {ar="فَاذْكُرُونِي أَذْكُرْكُمْ", ur="پس تم مجھے یاد رکھو، میں تمہیں یاد رکھوں گا", ref="Surah Al-Baqarah: 152"} }
local asmaNabi = { {ar="مُحَمَّد", ro="Muhammad", ur="بہت زیادہ تعریف کیا گیا"}, {ar="أَحْمَد", ro="Ahmad", ur="سب سے زیادہ تعریف کرنے والا"}, {ar="الْمَاحِي", ro="Al-Mahi", ur="کفر مٹانے والا"}, {ar="الْحَاشِر", ro="Al-Hashir", ur="جس کے بعد لوگ حشر کے لیے جمع ہوں گے"}, {ar="الْعَاقِب", ro="Al-Aqib", ur="سب سے آخری نبی"}, {ar="رَسُول الله", ro="Rasul Allah", ur="اللہ کے رسول"}, {ar="النَّبِيّ", ro="An-Nabi", ur="نبی"}, {ar="حَبِيب الله", ro="Habib Allah", ur="اللہ کے پیارے"}, {ar="المُصْطَفَى", ro="Al-Mustafa", ur="چنا ہوا"}, {ar="الأمِين", ro="Al-Ameen", ur="امانت دار"}, {ar="الصَّادِق", ro="As-Sadiq", ur="سچا"}, {ar="سِرَاجًا مُنِيرًا", ro="Sirajan Muneera", ur="روشن چراغ"}, {ar="رَحْمَة لِلْعَالَمِين", ro="Rahmatan lil-Alameen", ur="جہانوں کے لیے رحمت"}, {ar="شَاهِد", ro="Shahid", ur="گواہی دینے والا"}, {ar="مُبَشِّر", ro="Mubashshir", ur="خوشخبری دینے والا"}, {ar="نَذِير", ro="Nazir", ur="ڈرانے والا"}, {ar="دَاعِيًا إِلَى الله", ro="Da'iyan ilAllah", ur="اللہ کی طرف بلانے والا"}, {ar="طٰه", ro="Taha", ur="پاک، پاکیزہ"}, {ar="يٰسٓ", ro="Ya-Seen", ur="اے انسانوں کے سردار"}, {ar="خَاتَم النَّبِيِّين", ro="Khatam-un-Nabiyyeen", ur="نبیوں کے آخری"} }
local asmaUlHusna = {
{ar="الرَّحْمَٰنُ", ro="Ar-Rahman", ur="بہت مہربان"}, {ar="الرَّحِيمُ", ro="Ar-Raheem", ur="نہایت رحم والا"}, {ar="الْمَلِكُ", ro="Al-Malik", ur="بادشاہ"},
{ar="الْقُدُّوسُ", ro="Al-Quddus", ur="پاک ذات"}, {ar="السَّلَامُ", ro="As-Salam", ur="سلامتی دینے والا"}, {ar="الْمُؤْمِنُ", ro="Al-Mu'min", ur="امن دینے والا"},
{ar="الْمُهَيْمِنُ", ro="Al-Muhaymin", ur="نگہبان"}, {ar="الْعَزِيزُ", ro="Al-Aziz", ur="غالب"}, {ar="الْجَبَّارُ", ro="Al-Jabbar", ur="زبردست"},
{ar="الْمُتَكَبِّرُ", ro="Al-Mutakabbir", ur="بڑائی والا"}, {ar="الْخَالِقُ", ro="Al-Khaliq", ur="پیدا کرنے والا"}, {ar="الْبَارِئُ", ro="Al-Bari'", ur="جان ڈالنے والا"},
{ar="الْمُصَوِّرُ", ro="Al-Musawwir", ur="صورت بنانے والا"}, {ar="الْغَفَّارُ", ro="Al-Ghaffar", ur="بہت بخشنے والا"}, {ar="الْقَهَّارُ", ro="Al-Qahhar", ur="قہر ڈالنے والا"},
{ar="الْوَهَّابُ", ro="Al-Wahhab", ur="سب کچھ عطا کرنے والا"}, {ar="الرَّزَّاقُ", ro="Ar-Razzaq", ur="رزق دینے والا"}, {ar="الْفَتَّاحُ", ro="Al-Fattah", ur="کھولنے والا"},
{ar="اَلْعَلِيْمُ", ro="Al-Alim", ur="جاننے والا"}, {ar="الْقَابِضُ", ro="Al-Qabid", ur="تنگی کرنے والا"}, {ar="الْبَاسِطُ", ro="Al-Basit", ur="فراخی کرنے والا"},
{ar="الْخَافِضُ", ro="Al-Khafid", ur="پست کرنے والا"}, {ar="الرَّافِعُ", ro="Ar-Rafi'", ur="بلند کرنے والا"}, {ar="الْمُعِزُّ", ro="Al-Mu'izz", ur="عزت دینے والا"},
{ar="المذِلُّ", ro="Al-Mudhill", ur="ذلت دینے والا"}, {ar="السَّمِيعُ", ro="As-Sami'", ur="سننے والا"}, {ar="الْبَصِيرُ", ro="Al-Basir", ur="دیکھنے والا"},
{ar="الْحَكَمُ", ro="Al-Hakam", ur="فیصلہ کرنے والا"}, {ar="الْعَدْلُ", ro="Al-Adl", ur="انصاف کرنے والا"}, {ar="اللَّطِيفُ", ro="Al-Latif", ur="مہربان"},
{ar="الْخَبِيرُ", ro="Al-Khabir", ur="خبردار"}, {ar="الْحَلِيمُ", ro="Al-Halim", ur="بردبار"}, {ar="الْعَظِيمُ", ro="Al-Azim", ur="عظمت والا"},
{ar="الْغَفُورُ", ro="Al-Ghafur", ur="بہت بخشنے والا"}, {ar="الشَّكُورُ", ro="Ash-Shakur", ur="قدردان"}, {ar="الْعَلِيُّ", ro="Al-Ali", ur="بہت بلند"},
{ar="الْكَبِيرُ", ro="Al-Kabir", ur="بہت بڑا"}, {ar="الْحَفِيظُ", ro="Al-Hafiz", ur="حفاظت کرنے والا"}, {ar="المُقيِتُ", ro="Al-Muqit", ur="روزی پہنچانے والا"},
{ar="الْحَسِيبُ", ro="Al-Hasib", ur="حساب لینے والا"}, {ar="الْجَلِيلُ", ro="Al-Jalil", ur="بزرگ"}, {ar="الْكَرِيمُ", ro="Al-Karim", ur="کرم کرنے والا"},
{ar="الرَّقِيبُ", ro="Ar-Raqib", ur="نگہبان"}, {ar="الْمُجِيبُ", ro="Al-Mujib", ur="دعا قبول کرنے والا"}, {ar="الْوَاسِعُ", ro="Al-Wasi'", ur="وسعت والا"},
{ar="الْحَكِيمُ", ro="Al-Hakim", ur="حکمت والا"}, {ar="الْوَدُودُ", ro="Al-Wadud", ur="محبت کرنے والا"}, {ar="الْمَجِيدُ", ro="Al-Majid", ur="بزرگی والا"},
{ar="الْبَاعِثُ", ro="Al-Ba'ith", ur="اٹھانے والا"}, {ar="الشَّهِيدُ", ro="Ash-Shahid", ur="حاضر"}, {ar="الْحَقُّ", ro="Al-Haqq", ur="سچ"},
{ar="الْوَكِيلُ", ro="Al-Wakil", ur="کارساز"}, {ar="الْقَوِيُّ", ro="Al-Qawiyy", ur="طاقتور"}, {ar="الْمَتِينُ", ro="Al-Matin", ur="مضبوط"},
{ar="الْوَلِيُّ", ro="Al-Waliyy", ur="دوست"}, {ar="الْحَمِيدُ", ro="Al-Hamid", ur="تعریف کے لائق"}, {ar="الْمُحْصِي", ro="Al-Muhsi", ur="گننے والا"},
{ar="الْمُبْدِئُ", ro="Al-Mubdi'", ur="پہلی بار پیدا کرنے والا"}, {ar="الْمُعِيدُ", ro="Al-Mu'id", ur="دوبارہ پیدا کرنے والا"}, {ar="الْمُحْيِي", ro="Al-Muhyi", ur="زندہ کرنے والا"},
{ar="اَلْمُمِيتُ", ro="Al-Mumit", ur="مارنے والا"}, {ar="الْحَيُّ", ro="Al-Hayy", ur="ہمیشہ زندہ رہنے والا"}, {ar="الْقَيُّومُ", ro="Al-Qayyum", ur="قائم رکھنے والا"},
{ar="الْوَاجِدُ", ro="Al-Wajid", ur="پانے والا"}, {ar="الْمَاجِدُ", ro="Al-Majid", ur="بزرگی والا"}, {ar="الْوَاحِدُ", ro="Al-Wahid", ur="اکیلا"},
{ar="اَلْأَحَد", ro="Al-Ahad", ur="ایک"}, {ar="الصَّمَدُ", ro="As-Samad", ur="بے نیاز"}, {ar="الْقَادِرُ", ro="Al-Qadir", ur="قدرت والا"},
{ar="الْمُقْتَدِرُ", ro="Al-Muqtadir", ur="اقتدار والا"}, {ar="الْمُقَدِّمُ", ro="Al-Muqaddim", ur="آگے کرنے والا"}, {ar="الْمُؤَخِّرُ", ro="Al-Mu'akhkhir", ur="پیچھے کرنے والا"},
{ar="الأوَّلُ", ro="Al-Awwal", ur="سب سے پہلا"}, {ar="الْآخِرُ", ro="Al-Akhir", ur="سب سے آخری"}, {ar="الظَّاهِرُ", ro="Az-Zahir", ur="ظاہر"},
{ar="الْبَاطِنُ", ro="Al-Batin", ur="چھپا ہوا"}, {ar="الْوَالِي", ro="Al-Wali", ur="مالک"}, {ar="الْمُتَعَالِي", ro="Al-Muta'ali", ur="بہت بلند"},
{ar="الْبَرُّ", ro="Al-Barr", ur="بھلائی کرنے والا"}, {ar="التَّوَّابُ", ro="At-Tawwab", ur="توبہ قبول کرنے والا"}, {ar="الْمُنْتَقِمُ", ro="Al-Muntaqim", ur="انتقام لینے والا"},
{ar="العَفُوُّ", ro="Al-Afuww", ur="معاف کرنے والا"}, {ar="الرَّؤُوفُ", ro="Ar-Ra'uf", ur="شفقت کرنے والا"}, {ar="مَالِكُ الْمُلْكِ", ro="Malik-ul-Mulk", ur="ملک کا مالک"},
{ar="ذُوالْجَلَالِ وَالْإِكْرَامِ", ro="Dhul-Jalal-wal-Ikram", ur="جلال اور انعام والا"}, {ar="الْمُقْسِطُ", ro="Al-Muqsit", ur="انصاف کرنے والا"}, {ar="الْجَامِعُ", ro="Al-Jami'", ur="جمع کرنے والا"},
{ar="الْغَنِيُّ", ro="Al-Ghaniyy", ur="بے پرواہ"}, {ar="الْمُغْنِي", ro="Al-Mughni", ur="غنی کرنے والا"}, {ar="اَلْمَانِعُ", ro="Al-Mani'", ur="روکنے والا"},
{ar="الضَّارَّ", ro="Ad-Darr", ur="نقصان پہنچانے والا"}, {ar="النَّافِعُ", ro="An-Nafi'", ur="نفع پہنچانے والا"}, {ar="النُّورُ", ro="An-Nur", ur="روشنی کرنے والا"},
{ar="الْهَادِي", ro="Al-Hadi", ur="ہدایت دینے والا"}, {ar="الْبَدِيعُ", ro="Al-Badi'", ur="نئی طرح پیدا کرنے والا"}, {ar="اَلْبَاقِي", ro="Al-Baqi", ur="باقی رہنے والا"},
{ar="الْوَارِثُ", ro="Al-Warith", ur="وارث"}, {ar="الرَّشِيدُ", ro="Ar-Rashid", ur="ہدایت دینے والا"}, {ar="الصَّبُور", ro="As-Sabur", ur="صبر کرنے والا"}
}
local AIO = "https://archive.org/download/"
M.SF = function(x) return "archive.org (" .. x .. ")" end
local spotlightList = {}
do
local maxLen = math.max(#dailyAyahs, #asmaUlHusna, #asmaNabi, #surahNames)
for i=1, maxLen do
if dailyAyahs[i] then table.insert(spotlightList, {kind="ayah", data=dailyAyahs[i]}) end
if asmaUlHusna[i] then table.insert(spotlightList, {kind="allahname", data=asmaUlHusna[i]}) end
if asmaNabi[i] then table.insert(spotlightList, {kind="nabiname", data=asmaNabi[i]}) end
if surahNames[i] then table.insert(spotlightList, {kind="surah", data=surahNames[i], surahIdx=i}) end
end
end
M.pickSpotlight = function()
local idx = prefs.getInt("spotlightIndex", 0)
local item = spotlightList[(idx % #spotlightList) + 1]
prefs.edit().putInt("spotlightIndex", idx + 1).apply()
return item
end
local function dailyDuas()
if not _lazyCache.dailyDuas then
_lazyCache.dailyDuas = {
{cat="6 Kalme / Iman / Namaz", title='Kalima Tayyiba (Pehla Kalma)', en='Pehla Kalma - La ilaha illallah Muhammad-ur-Rasool-Allah.', ar='لا إله إلا الله محمد رسول الله', ur='پہلا کلمہ: اللہ کے سوا کوئی معبود نہیں، محمد ﷺ اللہ کے رسول ہیں', tip='Chhe Kalme - alag alag track (ek hi recording ka clip)', audio=AIO.."6KalimasUrduandEnglish/Recording%20Dec%204%202016%205%2015%2019%20AM%206%20Kalimas%20Urdu.mp3", src=M.SF("6 Kalimas Urdu and English"), startAt=0, cacheKey="6kalimas_full", endAt=300},
{cat="6 Kalme / Iman / Namaz", title='Kalima Shahadat (Doosra Kalma)', en='Doosra Kalma - the testimony of faith.', ar='أشهد أن لا إله إلا الله وحده لا شريك له وأشهد أن محمدا عبده ورسوله', ur='دوسرا کلمہ: گواہی کہ اللہ اکیلا ہے، اس کا کوئی شریک نہیں اور محمد ﷺ اس کے بندے اور رسول ہیں', tip='Chhe Kalme - alag alag track (ek hi recording ka clip)', audio=AIO.."6KalimasUrduandEnglish/Recording%20Dec%204%202016%205%2015%2019%20AM%206%20Kalimas%20Urdu.mp3", src=M.SF("6 Kalimas Urdu and English"), startAt=245, cacheKey="6kalimas_full", endAt=545},
{cat="6 Kalme / Iman / Namaz", title='Kalima Tamjeed (Teesra Kalma)', en='Teesra Kalma - glorification of Allah.', ar='سبحان الله والحمد لله ولا إله إلا الله والله أكبر', ur='تیسرا کلمہ: اللہ پاک ہے، سب تعریف اللہ کے لیے، اللہ کے سوا کوئی معبود نہیں، اللہ سب سے بڑا ہے', tip='Chhe Kalme - alag alag track (ek hi recording ka clip)', audio=AIO.."6KalimasUrduandEnglish/Recording%20Dec%204%202016%205%2015%2019%20AM%206%20Kalimas%20Urdu.mp3", src=M.SF("6 Kalimas Urdu and English"), startAt=368, cacheKey="6kalimas_full", endAt=668},
{cat="6 Kalme / Iman / Namaz", title='Kalima Tawheed (Chautha Kalma)', en='Chautha Kalma - the oneness of Allah.', ar='لا إله إلا الله وحده لا شريك له له الملك وله الحمد يحيي ويميت وهو حي لا يموت', ur='چوتھا کلمہ: اللہ کے سوا کوئی معبود نہیں، وہ اکیلا ہے، بادشاہی اور تعریف اسی کی ہے، وہی زندگی اور موت دیتا ہے', tip='Chhe Kalme - alag alag track (ek hi recording ka clip)', audio=AIO.."6KalimasUrduandEnglish/Recording%20Dec%204%202016%205%2015%2019%20AM%206%20Kalimas%20Urdu.mp3", src=M.SF("6 Kalimas Urdu and English"), startAt=1090, cacheKey="6kalimas_full", endAt=1390},
{cat="6 Kalme / Iman / Namaz", title='Kalima Istighfar (Paanchwa Kalma)', en='Paanchwa Kalma - seeking forgiveness.', ar='أستغفر الله ربي من كل ذنب وأتوب إليه', ur='پانچواں کلمہ: میں اپنے رب اللہ سے ہر گناہ کی معافی مانگتا ہوں اور اسی کی طرف رجوع کرتا ہوں', tip='Chhe Kalme - alag alag track (ek hi recording ka clip)', audio=AIO.."6KalimasUrduandEnglish/Recording%20Dec%204%202016%205%2015%2019%20AM%206%20Kalimas%20Urdu.mp3", src=M.SF("6 Kalimas Urdu and English"), startAt=1288, cacheKey="6kalimas_full", endAt=1588},
{cat="6 Kalme / Iman / Namaz", title='Kalima Radd-e-Kufr (Chhata Kalma)', en='Chhata Kalma - rejection of disbelief.', ar='اللهم إني أعوذ بك من أن أشرك بك شيئا وأنا أعلم به وأستغفرك لما لا أعلم به', ur='چھٹا کلمہ: اے اللہ! میں تیری پناہ مانگتا ہوں کہ کسی چیز کو تیرا شریک بناؤں اور تیری بخشش مانگتا ہوں', tip='Chhe Kalme - alag alag track (ek hi recording ka clip)', audio=AIO.."6KalimasUrduandEnglish/Recording%20Dec%204%202016%205%2015%2019%20AM%206%20Kalimas%20Urdu.mp3", src=M.SF("6 Kalimas Urdu and English"), startAt=1486, cacheKey="6kalimas_full", endAt=1786},
{cat="6 Kalme / Iman / Namaz", title='Namaz ka Sabaq - Namaz ki Ahmiyat (Importance)', en='Step-by-step Urdu lesson series (Shaykh Mufti Muhammad Saeed Khan).', ar='', ur='Namaz ka Sabaq - Namaz ki Ahmiyat (Importance)', tip='Alag alag track - har step ke liye alag audio', audio=AIO.."NamazSeriesByShaykhMuftiMuhammadSaeedKhan/Namaz01_Introduction_and_Importance_1.mp3", src=M.SF("Namaz ka Sabaq - Series (Shaykh Mufti Muhammad Saeed Khan)")},
{cat="6 Kalme / Iman / Namaz", title='Namaz ka Sabaq - Auqat-e-Namaz (Timings)', en='Step-by-step Urdu lesson series (Shaykh Mufti Muhammad Saeed Khan).', ar='', ur='Namaz ka Sabaq - Auqat-e-Namaz (Timings)', tip='Alag alag track - har step ke liye alag audio', audio=AIO.."NamazSeriesByShaykhMuftiMuhammadSaeedKhan/Namaz04_Auqat1.mp3", src=M.SF("Namaz ka Sabaq - Series (Shaykh Mufti Muhammad Saeed Khan)")},
{cat="6 Kalme / Iman / Namaz", title='Namaz ka Sabaq - Azan aur Iqamat', en='Step-by-step Urdu lesson series (Shaykh Mufti Muhammad Saeed Khan).', ar='', ur='Namaz ka Sabaq - Azan aur Iqamat', tip='Alag alag track - har step ke liye alag audio', audio=AIO.."NamazSeriesByShaykhMuftiMuhammadSaeedKhan/Namaz09_Azan_Iqamat-1.mp3", src=M.SF("Namaz ka Sabaq - Series (Shaykh Mufti Muhammad Saeed Khan)")},
{cat="6 Kalme / Iman / Namaz", title='Namaz ka Sabaq - Wuzu ka Tareeqa', en='Step-by-step Urdu lesson series (Shaykh Mufti Muhammad Saeed Khan).', ar='', ur='Namaz ka Sabaq - Wuzu ka Tareeqa', tip='Alag alag track - har step ke liye alag audio', audio=AIO.."NamazSeriesByShaykhMuftiMuhammadSaeedKhan/Namaz12-Wuzu-1.mp3", src=M.SF("Namaz ka Sabaq - Series (Shaykh Mufti Muhammad Saeed Khan)")},
{cat="6 Kalme / Iman / Namaz", title='Namaz ka Sabaq - Wuzu ke Masail', en='Step-by-step Urdu lesson series (Shaykh Mufti Muhammad Saeed Khan).', ar='', ur='Namaz ka Sabaq - Wuzu ke Masail', tip='Alag alag track - har step ke liye alag audio', audio=AIO.."NamazSeriesByShaykhMuftiMuhammadSaeedKhan/Namaz20-Wuzu-2.mp3", src=M.SF("Namaz ka Sabaq - Series (Shaykh Mufti Muhammad Saeed Khan)")},
{cat="6 Kalme / Iman / Namaz", title='Namaz ka Sabaq - Wuzu ki Sunnatain', en='Step-by-step Urdu lesson series (Shaykh Mufti Muhammad Saeed Khan).', ar='', ur='Namaz ka Sabaq - Wuzu ki Sunnatain', tip='Alag alag track - har step ke liye alag audio', audio=AIO.."NamazSeriesByShaykhMuftiMuhammadSaeedKhan/Namaz21-Wuzu-3.mp3", src=M.SF("Namaz ka Sabaq - Series (Shaykh Mufti Muhammad Saeed Khan)")},
{cat="6 Kalme / Iman / Namaz", title='Namaz ka Sabaq - Taharat ke Masail', en='Step-by-step Urdu lesson series (Shaykh Mufti Muhammad Saeed Khan).', ar='', ur='Namaz ka Sabaq - Taharat ke Masail', tip='Alag alag track - har step ke liye alag audio', audio=AIO.."NamazSeriesByShaykhMuftiMuhammadSaeedKhan/Namaz13_Taharat-1_Masail-e-Istanja.mp3", src=M.SF("Namaz ka Sabaq - Series (Shaykh Mufti Muhammad Saeed Khan)")},
{cat="6 Kalme / Iman / Namaz", title='Namaz ka Sabaq - Ghusl aur Sunnatain', en='Step-by-step Urdu lesson series (Shaykh Mufti Muhammad Saeed Khan).', ar='', ur='Namaz ka Sabaq - Ghusl aur Sunnatain', tip='Alag alag track - har step ke liye alag audio', audio=AIO.."NamazSeriesByShaykhMuftiMuhammadSaeedKhan/Namaz22-Bathing-Sunnatain.mp3", src=M.SF("Namaz ka Sabaq - Series (Shaykh Mufti Muhammad Saeed Khan)")},
{cat="6 Kalme / Iman / Namaz", title='Namaz ka Sabaq - Poora Tareeqa (Molana Mehboob Elahi)', en='Complete Urdu lesson on offering Salah, step by step.', ar='', ur='نماز کا مکمل سبق - مولانا محبوب الٰہی صاحب', tip='Poora tareeqa ek recording mein', audio=AIO.."molana-mehboob-elahi-namaz-ka-tareeqa-www.aswatalislam.net/Molana%20Mehboob%20Elahi%20-%20Namaz%20Ka%20Tareeqa%20%28www.aswatalislam.net%29.mp3", src=M.SF("Molana Mehboob Elahi")},
{cat="6 Kalme / Iman / Namaz", title='Namaz-e-Janaza ka Poora Tareeqa (Audio)', en='Complete method and masail of the funeral prayer, in Urdu.', ar='', ur='نماز جنازہ کا طریقہ اور مسائل', tip='Poora tareeqa sunne ke liye', audio=AIO.."Namaz-e-janazaKMasail-Www.bestrightway.com/Namaz-e-JanazaKMasail.mp3", src=M.SF("Namaz-e-Janaza k Masail")},
{cat="6 Kalme / Iman / Namaz", title='Namaz-e-Janaza - Pehli Takbeer', en='Janaza namaz ka pehla hissa - is clip mein 1 takbeer ka tareeqa aur uske baad ki dua.', ar='', ur='نماز جنازہ - 1 تکبیر', tip="Chhota clip - sirf 1 takbeer ka hissa (poora audio upar)", audio=AIO.."Namaz-e-janazaKMasail-Www.bestrightway.com/Namaz-e-JanazaKMasail.mp3", src=M.SF("Namaz-e-Janaza k Masail"), startAt=0, cacheKey="janaza_full", endAt=420},
{cat="6 Kalme / Iman / Namaz", title='Namaz-e-Janaza - Doosri Takbeer', en='Janaza namaz ka doosra hissa - is clip mein 2 takbeer ka tareeqa aur uske baad ki dua.', ar='', ur='نماز جنازہ - 2 تکبیر', tip="Chhota clip - sirf 2 takbeer ka hissa (poora audio upar)", audio=AIO.."Namaz-e-janazaKMasail-Www.bestrightway.com/Namaz-e-JanazaKMasail.mp3", src=M.SF("Namaz-e-Janaza k Masail"), startAt=420, cacheKey="janaza_full", endAt=840},
{cat="6 Kalme / Iman / Namaz", title='Namaz-e-Janaza - Teesri Takbeer', en='Janaza namaz ka teesra hissa - is clip mein 3 takbeer ka tareeqa aur uske baad ki dua.', ar='', ur='نماز جنازہ - 3 تکبیر', tip="Chhota clip - sirf 3 takbeer ka hissa (poora audio upar)", audio=AIO.."Namaz-e-janazaKMasail-Www.bestrightway.com/Namaz-e-JanazaKMasail.mp3", src=M.SF("Namaz-e-Janaza k Masail"), startAt=840, cacheKey="janaza_full", endAt=1260},
{cat="6 Kalme / Iman / Namaz", title='Namaz-e-Janaza - Chauthi Takbeer', en='Janaza namaz ka chautha hissa - is clip mein 4 takbeer ka tareeqa aur uske baad ki dua.', ar='', ur='نماز جنازہ - 4 تکبیر', tip="Chhota clip - sirf 4 takbeer ka hissa (poora audio upar)", audio=AIO.."Namaz-e-janazaKMasail-Www.bestrightway.com/Namaz-e-JanazaKMasail.mp3", src=M.SF("Namaz-e-Janaza k Masail"), startAt=1260, cacheKey="janaza_full", endAt=1680},
{cat="6 Kalme / Iman / Namaz", title='Iman-e-Mufassal', en='I believe in Allah, His Angels, His Books, His Messengers, the Last Day, and in Qadar - that good and evil are from Allah - and in the resurrection after death.', ar='آمَنْتُ بِاللَّهِ وَمَلَائِكَتِهِ وَكُتُبِهِ وَرُسُلِهِ وَالْيَوْمِ الْآخِرِ وَالْقَدْرِ خَيْرِهِ وَشَرِّهِ مِنَ اللَّهِ تَعَالَى وَالْبَعْثِ بَعْدَ الْمَوْتِ', ur='میں اللہ پر، اس کے فرشتوں پر، اس کی کتابوں پر، اس کے رسولوں پر، آخرت کے دن پر، اور تقدیر پر ایمان لایا', tip='Verified direct MP3 nahi mila - mukammal text + online link', audio="", src="", link="https://www.nooresunnat.com/Audios/iman-e-mufassal-in-english"},
{cat="6 Kalme / Iman / Namaz", title='Iman-e-Mujmal', en='I believe in Allah as He is, with His names and attributes, and I accept all His commands, with affirmation by the tongue and conviction in the heart.', ar='آمَنْتُ بِاللَّهِ كَمَا هُوَ بِأَسْمَائِهِ وَصِفَاتِهِ وَقَبِلْتُ جَمِيعَ أَحْكَامِهِ إِقْرَارٌ بِاللِّسَانِ وَتَصْدِيقٌ بِالْقَلْبِ', ur='میں اللہ پر ایمان لایا جیسا وہ اپنے ناموں اور صفات کے ساتھ ہے، اور اس کے تمام احکام قبول کیے', tip='Verified direct MP3 nahi mila - mukammal text + online link', audio="", src="", link="https://www.nooresunnat.com/Audios/iman-e-mujmal-with-translation"},
{cat="Khaana Peena", title="Khana Khane Ke Baad", en="All praise is for Allah, who fed me this and provided it for me without any power or strength on my part.", ar="الْحَمْدُ لِلَّهِ الَّذِي أَطْعَمَنِي هَٰذَا وَرَزَقَنِيهِ مِنْ غَيْرِ حَوْلٍ مِنِّي وَلَا قُوَّةٍ", ur="تمام تعریفیں اللہ کے لیے جس نے مجھے یہ کھلایا اور رزق دیا", tip="Khana khatam hone ke baad parhein", audio=AIO.."islamic-dua-in-audio/dua-after-eating.mp3", src=M.SF(BDIT)},
{cat="Khaana Peena", title="Doodh Peene Ke Baad", en="O Allah, bless it for us and give us more of it.", ar="اللَّهُمَّ بَارِكْ لَنَا فِيهِ وَزِدْنَا مِنْهُ", ur="اے اللہ اس میں برکت دے اور اس سے زیادہ عطا فرما", tip="Doodh peene ke khaas baad ki dua", audio="", src=""},
{cat="Sona Uthna", title="Sone Se Pehle Ki Dua", en="In Your name, O Allah, I die and I live.", ar="بِاسْمِكَ اللَّهُمَّ أَمُوتُ وَأَحْيَا", ur="اے اللہ! تیرے نام سے میں مرتا ہوں اور جیتا ہوں", tip="Bistar par lait kar dayin karwat par parhein (Sahih Bukhari)", audio=AIO.."islamic-dua-in-audio/dua-before-sleeping.mp3", audioAlternates={"https://archive.org/download/islamic-dua-in-audio/dua-before-sleeping.mp3"}, src=M.SF(BDIT), audioSrcAlt="archive.org (Islamic Duain - Masnoon Duain (Audio))"},
{cat="Sona Uthna", title="Neend Se Uthne Ki Dua", en="All praise is for Allah, who gave us life after causing us to die, and to Him is the resurrection.", ar="الْحَمْدُ لِلَّهِ الَّذِي أَحْيَانَا بَعْدَ مَا أَمَاتَنَا وَإِلَيْهِ النُّشُورُ", ur="تمام تعریفیں اللہ کے لیے جس نے ہمیں مارنے کے بعد زندہ کیا اور اسی کی طرف اٹھنا ہے", tip="Neend se uthte hi sab se pehle parhein", audio="https://www.thesufi.com/Islamic-Collection/Islamic_Audio_Section/67-Islamic-Masnoon-Dua-Arabic-with-Urdu-Translation-MP3/Dua-and-Supplications--8-.mp3", audioAlternates={"https://www.thesufi.com/Islamic-Collection/Islamic_Audio_Section/67-Islamic-Masnoon-Dua-Arabic-with-Urdu-Translation-MP3/Dua-and-Supplications--8-.mp3"}, src="TheSufi.com (Arabic+Urdu)", audioSrcAlt="TheSufi.com (Arabic+Urdu)"},
{cat="Sona Uthna", title="Karwat Badalte Waqt", en="There is no deity but Allah, the One, the Subduer, Lord of the heavens, earth, and all between them, the Almighty, the Forgiving.", ar="لَا إِلَٰهَ إِلَّا اللَّهُ الْوَاحِدُ الْقَهَّارُ رَبُّ السَّمَاوَاتِ وَالْأَرْضِ وَمَا بَيْنَهُمَا الْعَزِيزُ الْغَفَّارُ", ur="اللہ کے سوا کوئی معبود نہیں، وہ اکیلا غالب ہے، آسمانوں اور زمین اور جو ان کے درمیان ہے سب کا رب، عزت والا بخشنے والا", tip="Raat ko neend mein karwat lete waqt", audio="", src=""},
{cat="Baithna Ghar", title="Majlis Mein Baithne Ki Dua", en="Glory and praise be to You, O Allah. I bear witness there is no deity but You; I seek Your forgiveness and turn to You in repentance.", ar="سُبْحَانَكَ اللَّهُمَّ وَبِحَمْدِكَ أَشْهَدُ أَنْ لَا إِلَٰهَ إِلَّا أَنْتَ أَسْتَغْفِرُكَ وَأَتُوبُ إِلَيْكَ", ur="اے اللہ تو پاک ہے اور تیری ہی تعریف ہے، میں گواہی دیتا ہوں کہ تیرے سوا کوئی معبود نہیں، تجھ سے معافی مانگتا ہوں اور تیری طرف توبہ کرتا ہوں", tip="Kaffaratul Majlis - majlis se uthte waqt bhi parhein", audio="", src=""},
{cat="Hifazat", title="Sayyid-ul-Istighfar", en="O Allah, You are my Lord; there is no deity except You. You created me, and I am Your servant.", ar="اللَّهُمَّ أَنْتَ رَبِّي لَا إِلَٰهَ إِلَّا أَنْتَ خَلَقْتَنِي وَأَنَا عَبْدُكَ", ur="اے اللہ تو میرا رب ہے، تیرے سوا کوئی معبود نہیں، تو نے مجھے پیدا کیا اور میں تیرا بندہ ہوں", tip="Sab se afzal istighfar (Sahih Bukhari)", audio="", src=""},
{cat="Hifazat", title="Durood-e-Ibrahimi", en="O Allah, send blessings upon Muhammad and the family of Muhammad as You sent blessings upon Ibrahim and his family. You are Praiseworthy and Glorious.", ar="اللَّهُمَّ صَلِّ عَلَى مُحَمَّدٍ وَعَلَى آلِ مُحَمَّدٍ كَمَا صَلَّيْتَ عَلَى إِبْرَاهِيمَ وَعَلَى آلِ إِبْرَاهِيمَ إِنَّكَ حَمِيدٌ مَجِيدٌ", ur="اے اللہ محمد ﷺ اور ان کی آل پر رحمت نازل فرما جیسے ابراہیم اور ان کی آل پر نازل فرمائی، بیشک تو تعریف والا بزرگی والا ہے", tip="Namaz ke Tashahhud mein aur Juma ke din", audio="", src=""},
{cat="Hifazat", title="Ayatul Kursi", en="Allah—there is no deity except Him, the Ever-Living, the Sustainer of all.", ar="اللَّهُ لَا إِلَٰهَ إِلَّا هُوَ الْحَيُّ الْقَيُّومُ", ur="اللہ کے سوا کوئی معبود نہیں، وہ زندہ ہے اور سب کو قائم رکھنے والا ہے", tip="Har namaz ke baad aur sone se pehle", audio="", src=""},
{cat="Hifazat", title="Qul Huwallahu Ahad (Ikhlas)", en="Say: He is Allah, the One; Allah, the Eternal Refuge.", ar="قُلْ هُوَ اللَّهُ أَحَدٌ اللَّهُ الصَّمَدُ", ur="کہو وہ اللہ ایک ہے، اللہ بے نیاز ہے", tip="Hifazat ke liye 3 martaba", audio="", src=""},
{cat="Subah Shaam", title="Subah Ki Masnoon Dua (Full)", en="We have entered the morning, and all sovereignty belongs to Allah; all praise belongs to Allah.", ar="أَصْبَحْنَا وَأَصْبَحَ الْمُلْكُ لِلَّهِ وَالْحَمْدُ لِلَّهِ", ur="ہم نے صبح کی اور ساری بادشاہت اللہ کی ہے اور تمام تعریفیں اللہ ہی کے لیے ہیں", tip="Fajr ke baad", audio="", src=""},
{cat="Subah Shaam", title="Shaam Ki Masnoon Dua", en="We have entered the evening, and all sovereignty belongs to Allah; all praise belongs to Allah.", ar="أَمْسَيْنَا وَأَمْسَى الْمُلْكُ لِلَّهِ وَالْحَمْدُ لِلَّهِ", ur="ہم نے شام کی اور ساری بادشاہت اللہ کی ہے اور تمام تعریفیں اللہ ہی کے لیے ہیں", tip="Maghrib ke baad", audio="", src=""},
{cat="Safar", title="Safar Ki Dua", en="Glory be to the One who placed this at our service; we could not have done so ourselves, and to our Lord we will return.", ar="سُبْحَانَ الَّذِي سَخَّرَ لَنَا هَٰذَا وَمَا كُنَّا لَهُ مُقْرِنِينَ وَإِنَّا إِلَىٰ رَبِّنَا لَمُنْقَلِبُونَ", ur="پاک ہے وہ ذات جس نے ہمارے لیے اس سواری کو مسخر کیا اور ہم اس کے قابو میں لانے والے نہ تھے، اور بیشک ہم اپنے رب کی طرف لوٹنے والے ہیں", tip="Sawari par baithte waqt", audio="https://www.thesufi.com/Islamic-Collection/Islamic_Audio_Section/67-Islamic-Masnoon-Dua-Arabic-with-Urdu-Translation-MP3/Dua-and-Supplications--28-.mp3", audioAlternates={"https://www.thesufi.com/Islamic-Collection/Islamic_Audio_Section/67-Islamic-Masnoon-Dua-Arabic-with-Urdu-Translation-MP3/Dua-and-Supplications--28-.mp3"}, src="TheSufi.com (Arabic+Urdu)", audioSrcAlt="TheSufi.com (Arabic+Urdu)"},
{cat="Khaana Peena", title="Khana Khane Se Pehle", en="In the name of Allah.", ar="بِسْمِ اللَّهِ", ur="اللہ کے نام سے شروع", tip="Khana shuru karte waqt Bismillah", audio=AIO.."islamic-dua-in-audio/dua-before-eating.mp3", audioAlternates={"https://archive.org/download/islamic-dua-in-audio/dua-before-eating.mp3"}, src=M.SF(BDIT), audioSrcAlt="archive.org (Islamic Duain - Masnoon Duain (Audio))"},
{cat="Tahaarat", title="Wuzu Se Pehle", en="In the name of Allah.", ar="بِسْمِ اللَّهِ", ur="اللہ کے نام سے", tip="Wuzu shuru karte waqt", audio="", src=""},
{cat="Tahaarat", title="Wuzu Ke Baad", en="I bear witness there is no deity but Allah alone, without partner, and Muhammad is His servant and Messenger.", ar="أَشْهَدُ أَنْ لَا إِلَٰهَ إِلَّا اللَّهُ وَحْدَهُ لَا شَرِيكَ لَهُ وَأَشْهَدُ أَنَّ مُحَمَّدًا عَبْدُهُ وَرَسُولُهُ", ur="میں گواہی دیتا ہوں کہ اللہ کے سوا کوئی معبود نہیں وہ اکیلا ہے اس کا کوئی شریک نہیں اور محمد ﷺ اس کے بندے اور رسول ہیں", tip="Wuzu ke baad", audio="", src=""},
{cat="Masjid", title="Masjid Mein Dakhil Hone Ki Dua", en="O Allah, open for me the gates of Your mercy.", ar="اللَّهُمَّ افْتَحْ لِي أَبْوَابَ رَحْمَتِكَ", ur="اے اللہ میرے لیے اپنی رحمت کے دروازے کھول دے", tip="Masjid mein dakhil hote waqt", audio=AIO.."islamic-dua-in-audio/dua-for-entering-masjid.mp3", audioAlternates={"https://archive.org/download/islamic-dua-in-audio/dua-for-entering-masjid.mp3"}, src=M.SF(BDIT), audioSrcAlt="archive.org (Islamic Duain - Masnoon Duain (Audio))"},
{cat="Masjid", title="Masjid Se Nikalne Ki Dua", en="O Allah, I ask You for Your bounty.", ar="اللَّهُمَّ إِنِّي أَسْأَلُكَ مِنْ فَضْلِكَ", ur="اے اللہ میں تجھ سے تیرا فضل مانگتا ہوں", tip="Masjid se nikalte waqt", audio=AIO.."islamic-dua-in-audio/dua-for-exiting-masjid.mp3", audioAlternates={"https://archive.org/download/islamic-dua-in-audio/dua-for-exiting-masjid.mp3"}, src=M.SF(BDIT), audioSrcAlt="archive.org (Islamic Duain - Masnoon Duain (Audio))"},
{cat="Subah Shaam", title="Subah Ki Dua (Morning Prayer)", en="Morning supplication asking Allah for blessing and protection.", ar="", ur="Subah ki masnoon dua", tip="Fajr ke baad parhein", audio="https://www.thesufi.com/Islamic-Collection/Islamic_Audio_Section/67-Islamic-Masnoon-Dua-Arabic-with-Urdu-Translation-MP3/Dua-and-Supplications-Morning-Prayer.mp3", src="TheSufi.com (Arabic+Urdu)"},
{cat="Sona Uthna", title="Buri Neend/Darawana Khawab Aane Ki Dua", en="Supplication for seeking refuge and safety after a disturbing dream.", ar="", ur="Bura khawab ya neend ki bechaini ki dua", tip="Darawana khawab ane par parhein", audio="https://www.thesufi.com/Islamic-Collection/Islamic_Audio_Section/67-Islamic-Masnoon-Dua-Arabic-with-Urdu-Translation-MP3/Dua-and-Supplications--7-.mp3", src="TheSufi.com (Arabic+Urdu)"},
{cat="Namaz", title="Namaz Ke Baad Ki Dua", en="Supplication to be recited after completing the obligatory prayer.", ar="", ur="Namaz mukammal karne ke baad ki dua", tip="Har farz namaz ke baad", audio="https://www.thesufi.com/Islamic-Collection/Islamic_Audio_Section/67-Islamic-Masnoon-Dua-Arabic-with-Urdu-Translation-MP3/Dua-and-Supplications--15-.mp3", src="TheSufi.com (Arabic+Urdu)"},
{cat="Roza", title="Sehri Ki Dua", en="Supplication/intention associated with beginning the fast at Suhoor.", ar="", ur="Roza shuru karne (Sehri) ki niyat wali dua", tip="Sehri ke waqt parhein", audio="https://www.thesufi.com/Islamic-Collection/Islamic_Audio_Section/67-Islamic-Masnoon-Dua-Arabic-with-Urdu-Translation-MP3/Dua-and-Supplications--22-.mp3", src="TheSufi.com (Arabic+Urdu)"},
{cat="Roza", title="Iftar Ki Dua", en="Supplication for breaking the fast at Iftar.", ar="", ur="Roza kholte waqt ki dua", tip="Iftar ke waqt parhein", audio="https://www.thesufi.com/Islamic-Collection/Islamic_Audio_Section/67-Islamic-Masnoon-Dua-Arabic-with-Urdu-Translation-MP3/Dua-and-Supplications--23-.mp3", src="TheSufi.com (Arabic+Urdu)"},
{cat="Khaas Mawaqe", title="Dua-e-Haajit", en="Supplication asking Allah to fulfil a need.", ar="", ur="Zaroorat poori hone ki dua", tip="Kisi khaas zaroorat ke waqt", audio="https://www.thesufi.com/Islamic-Collection/Islamic_Audio_Section/67-Islamic-Masnoon-Dua-Arabic-with-Urdu-Translation-MP3/Dua-and-Supplications--1-.mp3", src="TheSufi.com (Arabic+Urdu)"},
{cat="Khaas Mawaqe", title="Fot Hone Par Taziyat Ki Dua", en="Supplication of condolence and patience after a death.", ar="", ur="Kisi ki wafat par sabr/taziyat ki dua", tip="Ghum ke waqt aur taziyat karte waqt", audio="https://www.thesufi.com/Islamic-Collection/Islamic_Audio_Section/67-Islamic-Masnoon-Dua-Arabic-with-Urdu-Translation-MP3/Dua-and-Supplications--55-.mp3", src="TheSufi.com (Arabic+Urdu)"},
{cat="Khaas Mawaqe", title="Kamyabi/Muqable Mein Kamyabi Ki Dua", en="Supplication asking Allah for help and success in a difficult task.", ar="", ur="Muqable ya mushkil mein kamyabi ki dua", tip="Imtihan ya mushkil kaam se pehle", audio="https://www.thesufi.com/Islamic-Collection/Islamic_Audio_Section/67-Islamic-Masnoon-Dua-Arabic-with-Urdu-Translation-MP3/Dua-and-Supplications--57-.mp3", src="TheSufi.com (Arabic+Urdu)"},
{cat="Khaas Mawaqe", title="Sabaat Aur Rehmat Ki Dua", en="Supplication asking Allah for steadfastness and mercy.", ar="", ur="Deen par sabaat (istiqamat) aur rehmat ki dua", tip="Rozmarra ki dua ke tor par", audio="https://www.thesufi.com/Islamic-Collection/Islamic_Audio_Section/67-Islamic-Masnoon-Dua-Arabic-with-Urdu-Translation-MP3/Dua-and-Supplications--58-.mp3", src="TheSufi.com (Arabic+Urdu)"},
{cat="Khaas Mawaqe", title="Barkat Aur Maghfirat Ki Dua", en="Supplication asking Allah for blessing and forgiveness.", ar="", ur="Barkat aur bakhshish maangne ki dua", tip="Rozmarra ki dua ke tor par", audio="https://www.thesufi.com/Islamic-Collection/Islamic_Audio_Section/67-Islamic-Masnoon-Dua-Arabic-with-Urdu-Translation-MP3/Dua-and-Supplications--64-.mp3", src="TheSufi.com (Arabic+Urdu)"},
{cat="Khaana Peena", title="Pani Peene Ke Baad Ki Dua", en="Supplication of thanks after drinking water.", ar="", ur="Pani peene ke baad ki masnoon dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-after-drinking-water.mp3", src=M.SF(BDIT)},
{cat="Khaana Peena", title="Dawat Mein Khana Khane Ke Baad Ki Dua", en="Supplication of thanks after eating at a host's meal.", ar="", ur="Kisi ki dawat mein khana khane ke baad ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-after-eating-dawat.mp3", src=M.SF(BDIT)},
{cat="Tahaarat", title="Bathroom Se Nikalne Ki Dua", en="Supplication upon leaving the bathroom.", ar="", ur="Bathroom/toilet se nikalne ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-after-exiting-from-the-toilet.mp3", src=M.SF(BDIT)},
{cat="Mausam", title="Baadal Chatne Ki Dua", en="Supplication for when clouds clear.", ar="", ur="Baadal chatne (khulne) ke waqt ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-after-opening-clouds.mp3", src=M.SF(BDIT)},
{cat="Khaas Mawaqe", title="Qarz Wapis Milne Ki Dua", en="Supplication of gratitude when a debt is repaid.", ar="", ur="Apna qarz wapis milne par shukr ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-after-receive-debts.mp3", src=M.SF(BDIT)},
{cat="Rozmarra", title="Naye Kapre Pehnne Ki Dua", en="Supplication upon wearing new clothes.", ar="", ur="Naye kapre pehante waqt ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-after-wearing-clothes.mp3", src=M.SF(BDIT)},
{cat="Rozmarra", title="Musafa (Handshake) Ki Dua", en="Supplication/greeting when meeting and shaking hands.", ar="", ur="Kisi se hath milate waqt ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-at-the-time-of-handshake.mp3", src=M.SF(BDIT)},
{cat="Rozmarra", title="Jamhai (Ubasi) Aane Ki Dua", en="Prophetic guidance associated with yawning.", ar="", ur="Ubasi/jamhai aane par karne wala amal", tip="", audio=AIO.."islamic-dua-in-audio/dua-at-the-time-of-jamahi.mp3", src=M.SF(BDIT)},
{cat="Mausam", title="Chand Grehan Ki Dua", en="Supplication and remembrance during a lunar eclipse.", ar="", ur="Chand grehan (lunar eclipse) ke waqt ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-at-the-time-of-lunar-eclipse.mp3", src=M.SF(BDIT)},
{cat="Mausam", title="Barish Ke Waqt Ki Dua (Audio)", en="Supplication when rain begins.", ar="", ur="Barish shuru hote waqt ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-at-the-time-of-rain.mp3", src=M.SF(BDIT)},
{cat="Rozmarra", title="Tohfa Milne Ki Dua", en="Supplication of thanks when receiving a gift.", ar="", ur="Kisi se tohfa (gift) milne par dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-at-the-time-of-receive-gift.mp3", src=M.SF(BDIT)},
{cat="Mausam", title="Suraj Grehan Ki Dua", en="Supplication and remembrance during a solar eclipse.", ar="", ur="Suraj grehan (solar eclipse) ke waqt ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-at-the-time-of-solar-eclipse.mp3", src=M.SF(BDIT)},
{cat="Mausam", title="Aandhi/Toofan Ki Dua", en="Supplication asking Allah for protection during strong wind or storm.", ar="", ur="Tez aandhi/toofan ke waqt ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-at-the-time-of-storm.mp3", src=M.SF(BDIT)},
{cat="Mausam", title="Suraj Nikalte Waqt Ki Dua", en="Morning remembrance at sunrise.", ar="", ur="Subah suraj nikalte waqt ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-at-the-time-of-sunrise.mp3", src=M.SF(BDIT)},
{cat="Mausam", title="Suraj Ghurub Hone Ki Dua", en="Evening remembrance at sunset.", ar="", ur="Shaam ko suraj ghurub hote waqt ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-at-the-time-of-sunset.mp3", src=M.SF(BDIT)},
{cat="Khaana Peena", title="Doodh Peene Se Pehle Ki Dua (Audio)", en="Supplication before drinking milk.", ar="", ur="Doodh peene se pehle ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-before-drinking-milk.mp3", src=M.SF(BDIT)},
{cat="Khaana Peena", title="Pani Peene Se Pehle Ki Dua (Audio)", en="Supplication before drinking water.", ar="", ur="Pani peene se pehle ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-before-drinking-water.mp3", src=M.SF(BDIT)},
{cat="Tahaarat", title="Bathroom Jaane Ki Dua", en="Supplication before entering the bathroom.", ar="", ur="Bathroom/toilet mein dakhil hone se pehle ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-before-entering-the-toilet.mp3", src=M.SF(BDIT)},
{cat="Rozmarra", title="Naya Kaam Shuru Karne Ki Dua", en="Supplication before beginning a new task.", ar="", ur="Koi naya kaam shuru karte waqt ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-before-starting-new-work.mp3", src=M.SF(BDIT)},
{cat="Khaas Mawaqe", title="Maghfirat Maangne Ki Dua", en="Supplication asking Allah for forgiveness.", ar="", ur="Allah se maghfirat maangne ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-for-asking-forgiveness.mp3", src=M.SF(BDIT)},
{cat="Baithna Ghar", title="Ghar Mein Dakhil Hone Ki Dua (Audio)", en="Supplication upon entering one's home.", ar="", ur="Ghar mein dakhil hote waqt ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-for-entering-house.mp3", src=M.SF(BDIT)},
{cat="Rozmarra", title="Bazaar Mein Dakhil Hone Ki Dua", en="Supplication upon entering the marketplace.", ar="", ur="Bazaar/market mein jaate waqt ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-for-entering-the-marketplace.mp3", src=M.SF(BDIT)},
{cat="Rozmarra", title="Shukriya Ada Karne Ki Dua", en="Supplication expressing gratitude.", ar="", ur="Kisi ka shukriya ada karte waqt ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-for-expressing-thanks.mp3", src=M.SF(BDIT)},
{cat="Ramzan", title="Ramzan Ke Pehle Ashre Ki Dua", en="Supplication for the first ten days of Ramadan.", ar="", ur="Ramzan ke pehle ashre (rehmat) ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-for-first-ashra-of-ramadan.mp3", src=M.SF(BDIT)},
{cat="Khaas Mawaqe", title="Qarz Utarne Ki Dua", en="Supplication asking Allah for help in repaying debt.", ar="", ur="Qarz jaldi utarne ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-for-payment-of-debt.mp3", src=M.SF(BDIT)},
{cat="Rozmarra", title="Surma Lagane Ki Dua", en="Supplication associated with applying kohl.", ar="", ur="Aankhon mein surma lagate waqt ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-for-putting-on-surma.mp3", src=M.SF(BDIT)},
{cat="Mausam", title="Barish Ke Liye Dua (Istisqa)", en="Supplication asking Allah to send beneficial rain.", ar="", ur="Barish na ho rahi ho to mangne ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-for-rain-to-come.mp3", src=M.SF(BDIT)},
{cat="Rozmarra", title="Kitab Parhne Ki Dua", en="Supplication before reading or studying.", ar="", ur="Koi kitab parhna shuru karne ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-for-reading-the-book.mp3", src=M.SF(BDIT)},
{cat="Ramzan", title="Ramzan Ke Dusre Ashre Ki Dua", en="Supplication for the middle ten days of Ramadan.", ar="", ur="Ramzan ke dusre ashre (maghfirat) ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-for-second-ashra-of-ramadan.mp3", src=M.SF(BDIT)},
{cat="Khaas Mawaqe", title="Kisi Ko Museebat Mein Dekh Kar Dua", en="Supplication when seeing someone afflicted by hardship.", ar="", ur="Kisi ko museebat/museebat zada dekh kar parhne ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-for-seeing-someone-in-difficulty.mp3", src=M.SF(BDIT)},
{cat="Ramzan", title="Ramzan Ke Teesre Ashre Ki Dua", en="Supplication for the final ten days of Ramadan.", ar="", ur="Ramzan ke teesre ashre (jahannam se azadi) ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-for-third-ashra-of-ramadan.mp3", src=M.SF(BDIT)},
{cat="Khaas Mawaqe", title="Mushkil/Museebat Ke Waqt Ki Dua", en="Supplication asking Allah for relief in hardship.", ar="", ur="Kisi mushkil ya museebat ke waqt ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-for-trouble.mp3", src=M.SF(BDIT)},
{cat="Rozmarra", title="Seerhi/Upar Chadhte Waqt Ki Dua", en="Remembrance while ascending stairs or a height.", ar="", ur="Upar chadhte (seerhi ya pahar) waqt ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-for-upstairs.mp3", src=M.SF(BDIT)},
{cat="Rozmarra", title="Aaina Dekhne Ki Dua", en="Supplication upon looking in a mirror.", ar="", ur="Aaine mein apni surat dekhte waqt ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-for-when-looking-in-a-mirror.mp3", src=M.SF(BDIT)},
{cat="Khaas Mawaqe", title="Gussa Aane Par Dua", en="Supplication seeking refuge from anger.", ar="", ur="Gussa aane par parhne ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-for-when-one-suffers-anger.mp3", src=M.SF(BDIT)},
{cat="Ramzan", title="Qurbani Ki Dua", en="Supplication said when offering a sacrifice.", ar="", ur="Qurbani karte waqt ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-of-qurbani.mp3", src=M.SF(BDIT)},
{cat="Ramzan", title="Shab-e-Qadr Ki Dua", en="Supplication for the Night of Decree.", ar="", ur="Shab-e-Qadr mein parhne ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-of-shab-e-qadr.mp3", src=M.SF(BDIT)},
{cat="Rozmarra", title="Cheenk Aane Ki Dua", en="Prophetic response/remembrance when sneezing.", ar="", ur="Khud ko cheenk aane par parhne ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-of-sneezing.mp3", src=M.SF(BDIT)},
{cat="Ramzan", title="Taraweeh Ki Dua", en="Supplication associated with Taraweeh prayers.", ar="", ur="Taraweeh ki namaz se mutaliq dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-of-taraweeh.mp3", src=M.SF(BDIT)},
{cat="Rozmarra", title="Kisi Musalman Ko Khush Dekh Kar Dua", en="Supplication when seeing a fellow Muslim cheerful.", ar="", ur="Kisi musalman bhai ko muskurate dekh kar dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-to-be-asked-upon-beholding-a-muslim-smiling.mp3", src=M.SF(BDIT)},
{cat="Jaanwar Ki Awaz", title="Murgh Ki Awaz Sun Kar Dua", en="Remembrance upon hearing a rooster crow.", ar="", ur="Murgh (rooster) ki awaz sun kar parhne ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-to-be-invoked-upon-hearing-the-crowing-of-a-rooster.mp3", src=M.SF(BDIT)},
{cat="Safar", title="Sawari Par Baithne Ki Dua (Audio)", en="Supplication upon mounting a vehicle or ride.", ar="", ur="Gaadi/sawari par baithte waqt ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-to-be-recited-after-being-settled-onto-a-carriage.mp3", src=M.SF(BDIT)},
{cat="Khaana Peena", title="Khana Saamne Rakhe Jaane Par Dua", en="Supplication when food is served.", ar="", ur="Khana saamne rakha jaye to parhne ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-to-be-recited-when-food-is-placed-before.mp3", src=M.SF(BDIT)},
{cat="Khaas Mawaqe", title="Bimari Mein Parhne Ki Dua", en="Supplication asking Allah for healing during illness.", ar="", ur="Bimari ke waqt parhne ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-to-be-recited-while-feeling-sick.mp3", src=M.SF(BDIT)},
{cat="Khaana Peena", title="Har Nawala Khane Ki Dua", en="Supplication/remembrance while eating each morsel.", ar="", ur="Har luqma/nawala khane par parhne ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-to-eat-every-morsel.mp3", src=M.SF(BDIT)},
{cat="Khaana Peena", title="Pehla Nawala Khane Ki Dua", en="Supplication before eating the first morsel.", ar="", ur="Khane ka pehla nawala uthate waqt ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-to-eat-first-morsel.mp3", src=M.SF(BDIT)},
{cat="Khaas Mawaqe", title="Thakan Dur Karne Ki Dua", en="Supplication asking Allah for relief from tiredness.", ar="", ur="Thakan mehsoos hone par parhne ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-to-get-rid-of-tiredness.mp3", src=M.SF(BDIT)},
{cat="Khaas Mawaqe", title="Waswase Se Bachne Ki Dua", en="Supplication seeking protection from intrusive whispers.", ar="", ur="Shaitani waswase se bachne ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-to-get-rid-of-waswas.mp3", src=M.SF(BDIT)},
{cat="Rozmarra", title="Musalman Se Milte Waqt Ki Dua", en="Greeting and supplication when meeting another Muslim.", ar="", ur="Kisi musalman bhai se milte waqt ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-to-meet-with-muslim.mp3", src=M.SF(BDIT)},
{cat="Mausam", title="Garaj (Thunder) Ke Waqt Ki Dua", en="Supplication upon hearing thunder.", ar="", ur="Baadal garajne (thunder) ke waqt ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-to-read-at-time-of-thunder.mp3", src=M.SF(BDIT)},
{cat="Chand Sitare", title="Chand Dekhne Ki Dua", en="Supplication upon seeing the moon.", ar="", ur="Chand dekhte waqt ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-to-see-moon.mp3", src=M.SF(BDIT)},
{cat="Chand Sitare", title="Sitare Dekhne Ki Dua", en="Remembrance upon observing the stars.", ar="", ur="Sitare dekhte waqt ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-to-see-stars.mp3", src=M.SF(BDIT)},
{cat="Masjid", title="Masjid Dekhte Hi Ki Dua", en="Remembrance upon seeing a mosque.", ar="", ur="Masjid nazar aate hi parhne ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-to-see-the-masjid.mp3", src=M.SF(BDIT)},
{cat="Khaana Peena", title="Phal Khane Ki Dua", en="Supplication before eating fruit.", ar="", ur="Naya phal khane se pehle ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-to-take-fruit.mp3", src=M.SF(BDIT)},
{cat="Jaanwar Ki Awaz", title="Gadhe Ki Awaz Sun Kar Dua", en="Supplication upon hearing a donkey bray.", ar="", ur="Gadhe (donkey) ki awaz sun kar parhne ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-upon-hearing-braying-of-a-donkey.mp3", src=M.SF(BDIT)},
{cat="Jaanwar Ki Awaz", title="Kutte Ke Bhonkne Ki Awaz Sun Kar Dua", en="Supplication upon hearing a dog bark.", ar="", ur="Kutte ke bhonkne ki awaz sun kar parhne ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-upon-hearing-the-barking-of-a-dog.mp3", src=M.SF(BDIT)},
{cat="Chand Sitare", title="Naya Chand Dekhne Ki Dua", en="Supplication upon sighting the new crescent.", ar="", ur="Mahine ka naya chand dekhte waqt ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-upon-sighting-the-new-moon.mp3", src=M.SF(BDIT)},
{cat="Baithna Ghar", title="Ghar Se Nikalte Waqt Ki Dua (Audio)", en="Supplication upon leaving home.", ar="", ur="Ghar se bahar nikalte waqt ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-when-exiting-the-home.mp3", src=M.SF(BDIT)},
{cat="Rozmarra", title="Kisi Ko Cheenkte Sun Kar Dua (Yarhamuk Allah)", en="Response when hearing another person sneeze.", ar="", ur="Kisi aur ko cheenkte sun kar jawab dena", tip="", audio=AIO.."islamic-dua-in-audio/dua-when-hearing-someone-sneeze.mp3", src=M.SF(BDIT)},
{cat="Chand Sitare", title="Tootay Hue Tare (Shooting Star) Dekhne Ki Dua", en="Remembrance when seeing a shooting star.", ar="", ur="Tootay hue tare ko dekh kar parhne ki dua", tip="", audio=AIO.."islamic-dua-in-audio/dua-when-seeing-shooting-star.mp3", src=M.SF(BDIT)},
{cat="Hajj", title="Takbeer-e-Tashreeq", en="Takbeer recited during the days of Tashreeq.", ar="", ur="Eid ke ayyam-e-tashreeq mein parhi jane wali takbeer", tip="", audio=AIO.."islamic-dua-in-audio/takbeer-e-tashreeq.mp3", src=M.SF(BDIT)},
{cat="Hajj", title="Talbiyah", en="Pilgrimage response recited in Ihram: ‘Here I am, O Allah, here I am.’", ar="", ur="Hajj/Umrah ke ihram ki talbiyah", tip="", audio=AIO.."islamic-dua-in-audio/talbiyah.mp3", src=M.SF(BDIT)},
{cat="Rabbana (Quranic Dua)", title="Allah Never Break His Promise", en="Our Lord, surely You will gather the people for a Day about which there is no doubt. Indeed, Allah does not fail in His promise.", ref="Quran 3:9", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/01%20Allah%20never%20break%20his%20promise.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="No Help For Zalimun", en="Our Lord, do not place us with the wrongdoing people.", ref="Quran 7:47", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/02%20No%20help%20for%20zalimun.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="Grant Us What You Promised", en="Our Lord, grant us what You promised through Your messengers, and do not disgrace us on the Day of Resurrection. Indeed, You do not fail in Your promise.", ref="Quran 3:194", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/03%20Grant%20us%20what%20You%20promised.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="We Believe", en="Our Lord, we have believed, so register us among the witnesses.", ref="Quran 5:83", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/04%20We%20believe.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="Provide Us Sustenance", en="O Allah, our Lord, send down to us a table spread with food from heaven, as a sign from You and a provision; You are the best of providers.", ref="Quran 5:114", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/05%20Provide%20us%20Sustenance.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="You Are The Best Judge", en="Our Lord, decide between us and our people in truth; You are the best of those who decide.", ref="Quran 7:89", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/06%20You%20are%20the%20best%20judge.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="Save Us By Your Mercy", en="Our Lord, make us not a trial for the wrongdoing people, and save us by Your mercy from the disbelieving people.", ref="Quran 10:85-86", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/07%20Save%20us%20by%20Your%20Mercy.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="Nothing Is Hidden From Allah", en="Our Lord, You know what we conceal and what we declare; nothing on earth or in heaven is hidden from Allah.", ref="Quran 14:38", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/08%20Nothing%20is%20hidden%20from%20Allah.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="We Fear Lest", en="Our Lord, indeed we fear that he may hasten against us or transgress.", ref="Quran 20:45", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/09%20We%20fear%20lest.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="Avert The Torment Of Hell", en="Our Lord, avert from us the punishment of Hell. Its punishment is ever adhering; indeed, it is an evil settlement and residence.", ref="Quran 25:65-66", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/10%20Avert%20the%20Torment%20of%20Hell.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="Leaders Of The Muttaqun", en="Our Lord, grant us from among our spouses and offspring comfort to our eyes, and make us an example for the righteous.", ref="Quran 25:74", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/11%20Leaders%20of%20the%20Muttaqun.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="Punish Us Not", en="Our Lord, do not impose blame on us if we forget or err.", ref="Quran 2:286", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/12%20Punish%20us%20not.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="Lay Not On Us A Burden", en="Our Lord, lay not upon us a burden like that which You laid upon those before us.", ref="Quran 2:286", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/13%20Lay%20not%20on%20us%20a%20Burden.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="Pardon And Grant Us Forgiveness", en="Our Lord, burden us not with what we cannot bear. Pardon us, forgive us, have mercy on us; You are our Protector, so help us against the disbelieving people.", ref="Quran 2:286", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/14%20Pardon%20and%20Grant%20us%20Forgiveness.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="Forgive Us Our Sins", en="Our Lord, we have believed, so forgive us our sins and protect us from the punishment of the Fire.", ref="Quran 3:16", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/15%20Forgive%20us%20our%20Sins.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="Victory Over Disbelievers", en="Our Lord, forgive us our sins and our excesses, make our feet firm, and grant us victory over the disbelieving people.", ref="Quran 3:147", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/16%20Victory%20over%20Disbelievers.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="Bestow Upon Us Your Mercy", en="Our Lord, let not our hearts deviate after You have guided us, and grant us mercy from Yourself. Indeed, You are the Bestower.", ref="Quran 3:8", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/17%20Bestow%20upon%20us%20Your%20Mercy.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="Forgive Me And My Parents", en="Our Lord, forgive me, my parents, and the believers on the Day the account is established.", ref="Quran 14:41", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/18%20Forgive%20me%20and%20my%20Parents.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="Grant Us Forgiveness", en="Our Lord, forgive us and our brothers who preceded us in faith, and place no resentment in our hearts toward those who believe.", ref="Quran 59:10", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/19%20Grant%20us%20Forgiveness.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="Give Us In This World Good", en="Our Lord, give us good in this world and good in the Hereafter, and protect us from the punishment of the Fire.", ref="Quran 2:201", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/20%20Give%20us%20in%20this%20World%20Good.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="Save Us From Fire", en="Our Lord, You did not create this aimlessly. Glory be to You; protect us from the punishment of the Fire.", ref="Quran 3:191", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/21%20Save%20us%20from%20Fire.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="Place Us Not With Zalimun", en="Our Lord, make us not a trial for the wrongdoing people.", ref="Quran 10:85", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/22%20Place%20us%20not%20with%20Zalimun.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="Make Them Enter The Paradise", en="Our Lord, admit them to the Gardens of Eternity You promised them, together with the righteous among their forefathers, spouses, and offspring. You are the Exalted in Might, the Wise.", ref="Quran 40:8", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/23%20Make%20them%20enter%20the%20Paradise.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="Bestow Mercy From Yourself", en="Our Lord, grant us mercy from Your presence and guide our affair to what is right.", ref="Quran 18:10", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/24%20Bestow%20Mercy%20from%20Yourself.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="We Believe, Forgive Us", en="Our Lord, we believe, so forgive us and have mercy on us; You are the best of the merciful.", ref="Quran 23:109", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/25%20We%20Believe%2C%20Forgive%20us.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="Forgive Us And Our Brethren", en="Our Lord, forgive us and our brothers who preceded us in faith, and place no resentment in our hearts toward those who believe.", ref="Quran 59:10", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/26%20Forgive%20us%20and%20our%20Brethren.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="Allah Is Full Of Kindness", en="Our Lord, You are indeed Kind and Merciful.", ref="Quran 59:10", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/27%20Allah%20is%20Full%20of%20Kindness.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="Make Us Not A Trail", en="Our Lord, make us not a trial for those who do wrong.", ref="Quran 10:85", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/28%20Make%20us%20not%20a%20Trail.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="Accept Our Repentance", en="Our Lord, we have wronged ourselves; if You do not forgive us and have mercy on us, we will surely be among the losers.", ref="Quran 7:23", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/29%20Accesp%20our%20Repentance.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="Let Not Our Hearts Deviate", en="Our Lord, let not our hearts deviate after You have guided us, and grant us mercy from Yourself.", ref="Quran 3:8", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/30%20Let%20not%20our%20Hearts%20Deviate.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="We Believe In What You Have Sent", en="Our Lord, we believe in what You revealed and follow the Messenger; write us among the witnesses.", ref="Quran 3:53", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/31%20We%20believe%20in%20what%20You%20have%20sent.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="Believe In Allah", en="Our Lord, we have heard a caller inviting us to faith: ‘Believe in your Lord,’ and we have believed.", ref="Quran 3:193", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/32%20Believe%20in%20Allah.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="Remit Our Evil Deeds", en="Our Lord, forgive our sins, remove our misdeeds, and cause us to die among the righteous.", ref="Quran 3:193", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/33%20Remit%20our%20Evil%20Deeds.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="Forgive Those Who Repent", en="Our Lord, You encompass all things in mercy and knowledge. Forgive those who repent and follow Your way, and protect them from Hellfire.", ref="Quran 40:7", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/34%20Forgive%20those%20who%20Repent.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="We Turn In Repentance", en="Our Lord, upon You we rely; to You we turn in repentance, and to You is the final destination.", ref="Quran 60:4", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/35%20We%20Turn%20in%20Repentance.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="Accept Our Service", en="Our Lord, accept this from us. Indeed, You are the All-Hearing, the All-Knowing.", ref="Quran 2:127", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/36%20Accept%20our%20Service.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="Give Us Patience", en="Our Lord, pour upon us patience, make our feet firm, and help us against the disbelieving people.", ref="Quran 2:250", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/37%20Give%20us%20Patience.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="To Die As Muslim", en="Our Lord, pour upon us patience and let us die as Muslims in submission to You.", ref="Quran 7:126", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/38%20To%20Die%20as%20Muslim.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="Accept My Invocation", en="My Lord, make me an establisher of prayer, and from my descendants as well. Our Lord, accept my supplication.", ref="Quran 14:40", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/39%20Accept%20my%20Invocation.mp3", src=M.SF("Rabbana 40 Supplications")},
{cat="Rabbana (Quranic Dua)", title="Allah Is Oft-Forgiving", en="Our Lord, perfect our light for us and forgive us. Indeed, You are over all things capable.", ref="Quran 66:8", ar="", ur="", tip="", audio=AIO.."Rabbana-40-Supplications/40%20Allah%20is%20Oft-Forgiving.mp3", src=M.SF("Rabbana 40 Supplications")},
}
end
return _lazyCache.dailyDuas
end
M.getDuaAudioLocal = function(d)
if d and d.book then return bookAudioDir .. tostring(d.cacheKey or "book") .. ".mp3" end
return duaAudioDir .. "dua_" .. slug(d.cacheKey or d.title) .. ".mp3"
end
local fullQuranVoices = { {name="Al-Minshawi (Moratal) + Urdu (Shamshad Ali Khan)", url="https://archive.org/download/FullQuranByALMINSHAWIMORAT356856856835635853xedUrduByShamshadAliKhan64kb/full%20-quran-by-__ALMINSHAWI-MORATAL__mixed_urdu-by-Shamshad-%20Ali-%20Khan-64kb.mp3", file="fullquran_minshawi_urdu.mp3"}, {name="Al-Hosary + Urdu (Shamshad Ali Khan)", url="https://archive.org/download/FullQuranByAlhosaryTeacherWithoutKidsMixedUr356858633568353535686535368duByShamshadAliKhan64kb/full%20-quran-by-__alhosary__teacher__without__kids__mixed_urdu-by-Shamshad-%20Ali-%20Khan-64kb.mp3", file="fullquran_alhosary_urdu.mp3"} }
M.getFullQuranLocal = function(v) return duaAudioDir .. v.file end
local function hadithBooks()
if not _lazyCache.hadithBooks then
_lazyCache.hadithBooks = {
{n=1, title="The Book Of Revelation", range="Hadith 1-7", file="Sahih Bukhari Book 01  The Book Of Revelation  Hadith 1-7 of 7563 English.mp3"},
{n=2, title="Belief (Faith)", range="Hadith 8-58", file="Sahih Bukhari Book 02  The Book Of Belief (Faith)  Hadith 8-58 of 7563 English.mp3"},
{n=3, title="Knowledge", range="Hadith 59-134", file="Sahih Bukhari Book 03  The Book Of Knowledge  Hadith 59-134 of 7563 English.mp3"},
{n=4, title="Ablutions (Wudu)", range="Hadith 135-247", file="Sahih Bukhari Book 04  The Book Of Ablutions (Wudu)  Hadith 135-247 of 7563 English.mp3"},
{n=5, title="Bathing (Ghusl)", range="Hadith 248-293", file="Sahih Bukhari Book 05  The Book Of Bathing (Ghusl)  Hadith 248-293 of 7563 English.mp3"},
{n=6, title="Menses", range="Hadith 294-333", file="Sahih Bukhari Book 06  The Book Of Menses  Hadith 294-333 of 7563 English.mp3"},
{n=7, title="Tayammum", range="Hadith 334-348", file="Sahih Bukhari Book 07  The Book Of Tayammum  Hadith 334-348 of 7563 English.mp3"},
{n=8, title="The Prayers (As-Salat)", range="Hadith 349-520", file="Sahih Bukhari Book 08  The Book Of The Prayers (As-Salat) Hadith 349-520 of 7563 English.mp3"},
{n=9, title="Times of the prayers & superiority", range="Hadith 521-602", file="Sahih Bukhari Book 09  The Book Of the times of the prayers and it's superiority Hadith 521-602 of 7563 English.mp3"},
{n=10, title="Adhan (Call to Prayers)", range="Hadith 603-875", file="Sahih Bukhari Book 10  The Book Of Adhan (Call to Prayers)  Hadith 603-875 of 7563 English.mp3"},
{n=11, title="Al-Jumuah (Friday)", range="Hadith 876-941", file="Sahih Bukhari Book 11  The Book Of Al-Jumuah (Friday) I Jumma Prayer  Hadith 876-941 of 7563 English.mp3"},
{n=12, title="Fear Prayer", range="Hadith 942-947", file="Sahih Bukhari Book 12  The Book Of Fear Prayer  Hadith 942-947 of 7563 English.mp3"},
{n=13, title="The two Eid (Prayers & Festivals)", range="Hadith 948-989", file="Sahih Bukhari Book 13  The Book Of the two Eid (Prayers and Festivals)  Hadith 948-989 of 7563 English.mp3"},
{n=14, title="Witr Prayer", range="Hadith 990-1004", file="Sahih Bukhari Book 14  The Book Of Witr Prayer  Hadith 990-1004 of 7563 English.mp3"},
{n=15, title="Invoking Allah for Rain (Istisqaa)", range="Hadith 1005-1039", file="Sahih Bukhari Book 15  The Book Of Invoking Allah for Rain (Istisqaa)  Hadith 1005-1039 of 7563 English.mp3"},
{n=16, title="Eclipses", range="Hadith 1040-1066", file="Sahih Bukhari Book 16  The Book Of Eclipses  Hadith 1040-1066 of 7563 English.mp3"},
{n=17, title="Prostration During Recitation of Quran", range="Hadith 1067-1079", file="Sahih Bukhari Book 17  The Book Of Prostration During The Recitation of the Quran Hadith 1067-1079 of 7563 English.mp3"},
{n=18, title="Abridged/shortened prayers (At-Taqsir)", range="Hadith 1080-1119", file="Sahih Bukhari Book 18  The Book Of abridged or shortened prayers (at-taqsir) Hadith 1080-1119 of 7563 English.mp3"},
{n=19, title="Night Prayer (Salat-ut-Tahajjud)", range="Hadith 1120-1187", file="Sahih Bukhari Book 19  The Book Of Night Prayer (Salat-ut-Tahajjud)  Hadith 1120-1187 of 7563 English.mp3"},
{n=20, title="Prayer at Masjid Makkah/Madinah", range="Hadith 1188-1197", file="Sahih Bukhari Book 20  The Superiority of Offering Prayer in the Sosque of  Makkah and al-Madinah H 1188-1197 of 7563 English.mp3"},
{n=21, title="Actions in the Prayer (As-Salat)", range="Hadith 1198-1223", file="Sahih Bukhari Book 21  The Book Of Dealing with Actions in the Prayer  (As-Salat) Hadith 1198-1223 of 7563 English.mp3"},
{n=22, title="Forgetfulness in Prayer (As-Sahw)", range="Hadith 1224-1236", file="Sahih Bukhari Book 22  The Book Of  Forgetfulness in Prayer (As-Sahw)  Hadith 1224-1236 of 7563 English.mp3"},
{n=23, title="Funerals (Al-Janaaiz)", range="Hadith 1237-1394", file="Sahih Bukhari Book 23  The Book Of Funerals (Al-Janaaiz)  Hadith 1237-1394 of 7563 English.mp3"},
{n=24, title="Zakat (Obligatory Charity Tax)", range="Hadith 1395-1512", file="Sahih Bukhari Book 24  The Book Of Zakat (Obligatory Charity Tax)  Hadith 1395-1512 of 7563 English.mp3"},
{n=25, title="Hajj (Pilgrimage to Makkah)", range="Hadith 1513-1772", file="Sahih Bukhari Book 25  The Book Of Hajj (Pilgrimage to Makkah)  Hadith 1513-1772 of 7563 English.mp3"},
{n=26, title="Al-Umrah (Minor pilgrimage)", range="Hadith 1773-1805", file="Sahih Bukhari Book 26  The Book Of Al-Umrah (Minor pilgrimage)  Hadith 1773-1805 of 7563 English.mp3"},
{n=27, title="Al-Muhsar (Pilgrims Prevented)", range="Hadith 1806-1820", file="Sahih Bukhari Book 27  The Book Of Al-Muhsar (Pilgrims Prevented from Completing the Pilgrimage) H 1806-1820 of 7563 English.mp3"},
{n=28, title="Penalty for hunting (by a muhrim)", range="Hadith 1821-1866", file="Sahih Bukhari Book 28  The Book Of penalty for hunting (by a muhrim) and similar things Hadith 1821-1866 of 7563 English.mp3"},
{n=29, title="Virtues of Madinah", range="Hadith 1867-1890", file="Sahih Bukhari Book 29  The Book Of Virtues of Madinah  Hadith 1867-1890 of 7563 English.mp3"},
{n=30, title="The Fasting (As Saum)", range="Hadith 1891-2007", file="Sahih Bukhari Book 30  The Book Of The Fasting (As Saum)  Hadith 1891-2007 of 7563 English.mp3"},
{n=31, title="Taraweeh Prayers (Ramadaan)", range="Hadith 2008-2013", file="Sahih Bukhari Book 31  The Book Of Taraweeh Prayers at Night in Ramadaan Hadith 2008-2013 of 7563 English.mp3"},
{n=32, title="Superiority of the Night of Qadr", range="Hadith 2014-2024", file="Sahih Bukhari Book 32  The Book Of Superiority of the Night of Qadr  Hadith 2014-2024 of 7563 English.mp3"},
{n=33, title="I'tikaf", range="Hadith 2025-2046", file="Sahih Bukhari Book 33  The Book Of Retiring to a Mosque for Remembrance of Allah (Itikaf) Hadith 2025-2046 of 7563 English.mp3"},
{n=34, title="Sales (Bargains)", range="Hadith 2047-2238", file="Sahih Bukhari Book 34  The Book Of Sales (Bargains)  Hadith 2047-2238 of 7563 English.mp3"},
{n=35, title="As-Salam (Goods Delivered Later)", range="Hadith 2239-2256", file="Sahih Bukhari Book 35  The Sales in Which a Price is Paid for Goods to be Delivered Later(As-Salam) Hadith 2239-2256 of 7563 English.mp3"},
{n=36, title="Ash-Shuf'a (Right of First Refusal)", range="Hadith 2257-2259", file="Sahih Bukhari Book 36  The Book Of Right of First Refusal, re-emption (ash-shuf'a) Hadith 2257-2259 of 7563 English.mp3"},
{n=37, title="Hiring", range="Hadith 2260-2286", file="Sahih Bukhari Book 37  The Book Of Hiring (Concerning Hiring)  Hadith 2260-2286 of 7563 English.mp3"},
{n=38, title="Al-Hawaalat (Transfer of Debt)", range="Hadith 2287-2289", file="Sahih Bukhari Book 38  The Book Of Transferance of a Debt from One Person to Another (Al-Hawaalat) H 2287-2289 of 7563 English.mp3"},
{n=39, title="Kafalah", range="Hadith 2290-2298", file="Sahih Bukhari Book 39  The Book Of Kafalah  Hadith 2290-2298 of 7563 English.mp3"},
{n=40, title="Representation/Authorization", range="Hadith 2299-2319", file="Sahih Bukhari Book 40  The Book Of Representation (or Authorization)  Hadith 2299-2319 of 7563 English.mp3"},
{n=41, title="Cultivation and Agriculture", range="Hadith 2320-2350", file="Sahih Bukhari Book 41  The Book Of Cultivation and Agriculture  Hadith 2320-2350 of 7563 English.mp3"},
{n=42, title="Watering (Distribution of Water)", range="Hadith 2351-2384", file="Sahih Bukhari Book 42  The Book Of Watering (Distribution of Water) Hadith 2351-2384 of 7563 English.mp3"},
{n=43, title="Loans, Freezing of Property, Bankruptcy", range="Hadith 2385-2409", file="Sahih Bukhari Book 43  The Book Of Loans, payment of loans, Freezing of Property, Bankruptcy Hadith 2385-2409 of 7563.mp3"},
{n=44, title="Quarrels, disputes (Khusoomaat)", range="Hadith 2410-2425", file="Sahih Bukhari Book 44  The Book Of quarrels, disputes (Khusoomaat) Hadith 2410-2425 of7563 English.mp3"},
{n=45, title="Lost Things (Al-Luqatah)", range="Hadith 2426-2439", file="Sahih Bukhari Book 45  The Book Of Lost Things Picked up by Someone (Al-Luqatah)  Hadith 2426-2439 English.mp3"},
{n=46, title="Oppressions, Injustices (Al-Mazalim)", range="Hadith 2440-2482", file="Sahih Bukhari Book 46  The Book Of Oppressions, Injustices (Al-Mazalim)  Hadith 2440-2482 of 7563 English.mp3"},
{n=47, title="Partnership", range="Hadith 2483-2507", file="Sahih Bukhari Book 47  The Book Of Partnership  Hadith 2483-2507 of 7563 English.mp3"},
{n=48, title="Mortgaging in settled population", range="Hadith 2508-2516", file="Sahih Bukhari Book 48  The Book Of mortgaging in places occupied by settled population Hadith 2508-2516 of 7563 English.mp3"},
{n=49, title="Manumission of Slaves", range="Hadith 2517-2559", file="Sahih Bukhari Book 49  The Book Of Manumission of Slaves  Hadith 2517-2559 of 7563 English.mp3"},
{n=50, title="Al Mukatab", range="Hadith 2560-2565", file="Sahih Bukhari Book 50  The Book Of Al Mukatab  Hadith 2560-2565 of 7563 English.mp3"},
{n=51, title="Gifts & their superiority", range="Hadith 2566-2636", file="Sahih Bukhari Book 51  The Book Of gifts and the superiority of giving gifts  H 2566-2636 of 7563 English.mp3"},
{n=52, title="Witnesses, Testimonies", range="Hadith 2637-2689", file="Sahih Bukhari Book 52  The Book Of Witnesses, Testimonies  Hadith 2637-2689 of 7563 English.mp3"},
{n=53, title="Peacemaking, Reconciliation", range="Hadith 2690-2710", file="Sahih Bukhari Book 53  The Book Peacemaking, Reconciliation  Hadith 2690-2710 of 7563 English.mp3"},
{n=54, title="Conditions", range="Hadith 2711-2737", file="Sahih Bukhari Book 54  The Book Of Conditions  Hadith 2711-2737 of 7563 English.mp3"},
{n=55, title="Wills and Testaments (Wasaayaa)", range="Hadith 2738-2781", file="Sahih Bukhari Book 55  The Book Of Wills and Testaments (Wasaayaa) Hadith 2738-2781 of 7563 English.mp3"},
{n=56, title="Fighting for the Cause of Allah (Jihad)", range="Hadith 2782-3090", file="Sahih Bukhari Book 56  The Book Of Fighting for the Cause of Allah (Jihad)  Hadith 2782-3090 of 7563 English.mp3"},
{n=57, title="Khumus (One-fifth of Booty)", range="Hadith 3091-3155", file="Sahih Bukhari Book 57  The Book Of One-fifth of Booty to the Cause of Allah (Obligations of Khumus) H 3091-3155 of 7563 English.mp3"},
{n=58, title="Al-Jizya and Stoppage of War", range="Hadith 3156-3189", file="Sahih Bukhari Book 58  The Book of Al-Jizya and Stoppage of War  Hadith 3156-3189 of 7563 English.mp3"},
{n=59, title="The Beginning of Creation", range="Hadith 3190-3325", file="Sahih Bukhari Book 59  The Book of The Beginning of Creation  Hadith 3190-3325 of 7563 English.mp3"},
{n=60, title="Stories of the Prophets", range="Hadith 3326-3488", file="Sahih Bukhari Book 60  The Book Of The stories of the Prophets  Hadith  3326-3488 of 7563 English.mp3"},
{n=61, title="Virtues of the Prophet & Companions", range="Hadith 3489-3648", file="Sahih Bukhari Book 61  The Book Of Virtues and Merits of the Prophet (pbuh) and his Companions Hadith 3489-3648 of 7563 English.mp3"},
{n=62, title="Virtues of the Companions", range="Hadith 3649-3775", file="Sahih Bukhari Book 62  The Book Of The Virtues and merits of the Companions of the Prophet (PBUH) H 3649-3775 of 7563 English.mp3"},
{n=63, title="Merits of the Helpers (Al-Ansaar)", range="Hadith 3776-3948", file="Sahih Bukhari Book 63  The Book Of Merits of the Helpers in Madinah (Al-Ansaar)  Hadith 3776-3948 of 7563 English.mp3"},
{n=64, title="Holy Battles (Al-Maghaazi)", range="Hadith 3949-4473", file="Sahih Bukhari Book 64  The Book Of Holy Battles (Al-Maghaazi)  Hadith 3949-4473 of 7563 English.mp3"},
{n=65, title="Commentary on the Quran (Tafsir)", range="Hadith 4474-4977", file="Sahih Bukhari Book 65  The Book Of Commentary on the Quran ( Tafsir) Hadith 4474-4977 of 7563 English.mp3"},
{n=66, title="Virtues of the Quran", range="Hadith 4978-5062", file="Sahih Bukhari Book 66  The Book Of The Virtues of the Quran  Hadith 4978-5062 of 7563 English.mp3"},
{n=67, title="The Wedlock, Marriage (Nikaah)", range="Hadith 5063-5250", file="Sahih Bukhari Book 67  The Book Of The Wedlock, Marriage (Nikaah)  Hadith 5063-5250 of7563 English.mp3"},
{n=68, title="Divorce", range="Hadith 5251-5350", file="Sahih Bukhari Book 68  The Book Of Divorce  Hadith 5251-5350 of 7563 English.mp3"},
{n=69, title="Provision, Expenditures", range="Hadith 5351-5372", file="Sahih Bukhari Book 69  The Book Of Provision, Expenditures (Supporting the Family) Hadith 5351-5372 of 7563 English.mp3"},
{n=70, title="Foods, Meals", range="Hadith 5373-5466", file="Sahih Bukhari Book 70  The Book Of Foods, Meals  Hadith 5373-5466 of 7563 English.mp3"},
{n=71, title="Sacrifice on Occasion of Birth (Aqiqa)", range="Hadith 5467-5474", file="Sahih Bukhari Book 71  The Book Of Sacrifice on Occasion of Birth (Aqiqa) Hadith 5467-5474 of7563 English.mp3"},
{n=72, title="Slaughtering and Hunting", range="Hadith 5475-5544", file="Sahih Bukhari Book 72  The Book Of Slaughtering and Hunting  Hadith 5475-5544 of 7563 English.mp3"},
{n=73, title="Sacrifices (Al-Adaahi)", range="Hadith 5545-5574", file="Sahih Bukhari Book 73  The Book Of Sacrifices (Al-Adaahi)  Hadith 5545-5574 of 7563 English.mp3"},
{n=74, title="Drinks", range="Hadith 5475-5639", file="Sahih Bukhari Book 74  The Book Of Drinks  Hadith 5475-5639 of 7563 English.mp3"},
{n=75, title="Patients", range="Hadith 5640-5677", file="Sahih Bukhari Book 75  The Book Of Patients  Hadith 5640-5677 of 7563 English.mp3"},
{n=76, title="Medicine", range="Hadith 5678-5782", file="Sahih Bukhari Book 76  The Book Of Medicine  Hadith 5678-5782 of 7563 English.mp3"},
{n=77, title="Dress", range="Hadith 5783-5969", file="Sahih Bukhari Book 77  The Book Of Dress  Hadith 5783-5969 of 7563 English.mp3"},
{n=78, title="Good Manners (Al-Adab)", range="Hadith 5970-6226", file="Sahih Bukhari Book 78  The Book Of Good Manners (Al-Adab)  Hadith 5970-6226 of 7563 English.mp3"},
{n=79, title="Asking Permission to Enter", range="Hadith 6227-6303", file="Sahih Bukhari Book 79  The Book Of asking permission (to enter somebody else's dwelling place) Hadith 6227-6303 of 7563 English.mp3"},
{n=80, title="Invocations (Du'a's)", range="Hadith 6304-6411", file="Sahih Bukhari Book 80  The Book Of Invocations or Dua  (Du'a's)  Hadith 6304-6411 of 7563 English.mp3"},
{n=81, title="Softening of the hearts (Ar-Riqaq)", range="Hadith 6412-6593", file="Sahih Bukhari Book 81  The Book Of Softening of the hearts (Ar-Riqaq)  Hadith 6412-6593 of 7563 English.mp3"},
{n=82, title="Divine Preordainment (Al-Qadar)", range="Hadith 6594-6620", file="Sahih Bukhari Book 82  The Book Of Divine Preordainment (Al-Qadar)  Hadith 6594-6620 of 7563 English.mp3"},
{n=83, title="Oaths and Vows", range="Hadith 6621-6707", file="Sahih Bukhari Book 83  The Book Of Oaths and Vows  Hadith 6621-6707 of 7563 English.mp3"},
{n=84, title="Expiation of Unfulfilled Oaths", range="Hadith 6708-6723", file="Sahih Bukhari Book 84  The Book Of Expiation of Unfulfilled Oaths  Hadith 6708-6723 of 7563 English.mp3"},
{n=85, title="Laws of Inheritance (Al-Faraaid)", range="Hadith 6724-6771", file="Sahih Bukhari Book 85  The Book Of Laws of Inheritance (Al-Faraaid)  Hadith 6724-6771 of 7563 English.mp3"},
{n=86, title="Limits/Punishments (Hudood)", range="Hadith 6772-6860", file="Sahih Bukhari Book 86  The Book Of Limits and Punishments set by Allah (Hudood)  Hadith 6772-6860 of 7563 English.mp3"},
{n=87, title="Blood Money (Ad-Diyat)", range="Hadith 6861-6917", file="Sahih Bukhari Book 87  The Book Of Blood Money (Ad-Diyat)  Hadith 6861-6917 of 7563 English.mp3"},
{n=88, title="Obliging the Apostates & Repentance", range="Hadith 6918-6939", file="Sahih Bukhari Book 88  The Book Of Obliging the Apostates and Repentance of... Hadith 6918-6939 of 7563 English.mp3"},
{n=89, title="Al-Ikrah (Coercion)", range="Hadith 6940-6952", file="Sahih Bukhari Book 89  The Book Of Al-Ikrah (Coercion) (saying some-thing under compulsion) H 6940-6952 of 7563 English.mp3"},
{n=90, title="Tricks", range="Hadith 6953-6981", file="Sahih Bukhari Book 90  The Book Of Tricks  Hadith 6953-6981 of 7563 English.mp3"},
{n=91, title="Interpretation of Dreams", range="Hadith 6982-7047", file="Sahih Bukhari Book 91  The Book Of the Interpretation of Dreams  Hadith 6982-7047 of 7563 English.mp3"},
{n=92, title="Fitan (Trials and afflictions)", range="Hadith 7048-7136", file="Sahih Bukhari Book 92  The Book Of Fitan (Trials and afflictions)  Hadith 7048-7136 of 7563English.mp3"},
{n=93, title="Judgments (Al-Ahkaam)", range="Hadith 7137-7225", file="Sahih Bukhari Book 93  The Book Of Judgments (Al-Ahkaam)  Hadith 7137-7225 of 7563 English.mp3"},
{n=94, title="Wishes", range="Hadith 7226-7245", file="Sahih Bukhari Book 94  The Book Of Wishes  Hadith 7226-7245 of 7563 English.mp3"},
{n=95, title="Information Given by One Person", range="Hadith 7246-7267", file="Sahih Bukhari Book 95  The Book Of The Information Given by one Person  Hadith 7246-7267 of 7563 English.mp3"},
{n=96, title="Holding Fast to the Quran & Sunnah", range="Hadith 7268-7370", file="Sahih Bukhari Book 96  The Book Of Holding Fast to the Quran and Sunnah  Hadith 7268-7370 of 7563 English.mp3"},
{n=97, title="Islamic Monotheism (Tawhid)", range="Hadith 7371-7563", file="Sahih Bukhari Book 97  The Book Of Islamic Monotheism (Tawhid  Tawheed)  Hadith 7371-7563 of 7563 English.mp3"}
}
end
return _lazyCache.hadithBooks
end
M.buildHadithUrl = function(b) return URLBASES.hadith .. urlEncodeBytes(b.file) end
M.getHadithLocal = function(b) return duaAudioDir .. "hadith_bukhari_" .. b.n .. ".mp3" end
M.israrTafseerFiles = function()
if not _lazyCache.israrTafseer then
_lazyCache.israrTafseer = {
{n=0, title="Introduction (Bayan-ul-Quran)", file="000-Introduction -Bayan-ul-Quran.mp3"},
{n=1, title=surahNames[1], file="001-AL-FAATIHAH.mp3"}, {n=2, title=surahNames[2], file="002- AL-BAQARAH.mp3"},
{n=3, title=surahNames[3], file="003- ALE-IMRAN.mp3"}, {n=4, title=surahNames[4], file="004- AN-NISAA.mp3"},
{n=5, title=surahNames[5], file="005- AL-MAIDAH.mp3"}, {n=6, title=surahNames[6], file="006- AL-AN'AAM.mp3"},
{n=7, title=surahNames[7], file="007- AL-A'RAAF.mp3"}, {n=8, title=surahNames[8], file="008- AL-ANFAAL.mp3"},
{n=9, title=surahNames[9], file="009- AT-TAUBAH.mp3"}, {n=10, title=surahNames[10], file="010-YOUNUS.mp3"},
{n=11, title=surahNames[11], file="011-HUD.MP3"}, {n=12, title=surahNames[12], file="012-YOUSUF.mp3"},
{n=13, title=surahNames[13], file="013-AR-RAAD.mp3"}, {n=14, title=surahNames[14], file="014-IBRAHEEM.mp3"},
{n=15, title=surahNames[15], file="015-AL-HIJR.mp3"}, {n=16, title=surahNames[16], file="016-AH NAHL.mp3"},
{n=17, title=surahNames[17], file="017- BANI-ISRAIL.mp3"}, {n=18, title=surahNames[18], file="018-AL-KAHEF.mp3"},
{n=19, title=surahNames[19], file="019-MARYAM.mp3"}, {n=20, title=surahNames[20], file="020-TAA HAA.mp3"},
{n=21, title=surahNames[21], file="021-AL-AMBIA.mp3"}, {n=22, title=surahNames[22], file="022-AL-HAJJ.mp3"},
{n=23, title=surahNames[23], file="023-AL-MOMINOON.mp3"}, {n=24, title=surahNames[24], file="024-AN-NOOR.mp3"},
{n=25, title=surahNames[25], file="025-AL-FURQAN.mp3"}, {n=26, title=surahNames[26], file="026-AS-SHUARAA.mp3"},
{n=27, title=surahNames[27], file="027-AN-NAML.mp3"}, {n=28, title=surahNames[28], file="028-AL-QASES.mp3"},
{n=29, title=surahNames[29], file="029-AL-ANKABOOT.mp3"}, {n=30, title=surahNames[30], file="030-AR-ROOM.mp3"},
{n=31, title=surahNames[31], file="031-LUQMAN.mp3"}, {n=32, title=surahNames[32], file="032-AS-SAJDAH.mp3"},
{n=33, title=surahNames[33], file="033-AL-AHZAB.mp3"}, {n=34, title=surahNames[34], file="034-SABA.MP3"},
{n=35, title=surahNames[35], file="035-FAATIR.mp3"}, {n=36, title=surahNames[36], file="036-YAA SEEN.mp3"},
{n=37, title=surahNames[37], file="037-AS-SAFFAAT.mp3"}, {n=38, title=surahNames[38], file="038-SUAD.MP3"},
{n=39, title=surahNames[39], file="039-AZ-ZUMAR.mp3"}, {n=40, title=surahNames[40], file="040-AL-MOMIN.mp3"},
{n=41, title=surahNames[41], file="041-HAA MEEM AS-SAJDAH.mp3"}, {n=42, title=surahNames[42], file="042-AS-SHURA.mp3"},
{n=43, title=surahNames[43], file="043-AZ-ZUKHRUF.mp3"}, {n=44, title=surahNames[44], file="044-AD-DUKHAN.mp3"},
{n=45, title=surahNames[45], file="045-AL-JATHIA.mp3"}, {n=46, title=surahNames[46], file="046-AL-AHQAAF.mp3"},
{n=47, title=surahNames[47], file="047-MUHAMMAD.mp3"}, {n=48, title=surahNames[48], file="048-AL-FATH.mp3"},
{n=49, title=surahNames[49], file="049-AL-HUJURAAT.mp3"}, {n=50, title=surahNames[50], file="050-QAAF.MP3"},
{n=51, title=surahNames[51], file="051-AZ-ZARIYAAT.mp3"}, {n=52, title=surahNames[52], file="052-AT-TOOR.mp3"},
{n=53, title=surahNames[53], file="053-AN-NAJM.mp3"}, {n=54, title=surahNames[54], file="054-AL-QAMAR.mp3"},
{n=55, title=surahNames[55], file="055-AR-RAHMAN.mp3"}, {n=56, title=surahNames[56], file="056-AL-WAQIAH.mp3"},
{n=57, title=surahNames[57], file="057-AL-HADEED.mp3"}, {n=58, title=surahNames[58], file="058-AL-MUJADILAH.mp3"},
{n=59, title=surahNames[59], file="059-AL-HASHR.mp3"}, {n=60, title=surahNames[60], file="060-AL-MUMTAHINAH.mp3"},
{n=61, title=surahNames[61], file="061-AS-SAFF.mp3"}, {n=62, title=surahNames[62], file="062-AL-JUMUAH.mp3"},
{n=63, title=surahNames[63], file="063-AL-MUNAFIQOON.mp3"}, {n=64, title=surahNames[64], file="064-AT-TAGHABUN.mp3"},
{n=65, title=surahNames[65], file="065-AT-TALAAQ.mp3"}, {n=66, title=surahNames[66], file="066-AT-TAHREEM.mp3"},
{n=67, title=surahNames[67], file="067-AL-MULK.mp3"}, {n=68, title=surahNames[68], file="068-AL-QALAM.mp3"},
{n=69, title=surahNames[69], file="069-AL-HAAQ-QAH.mp3"}, {n=70, title=surahNames[70], file="070-AL-MAARIJ.mp3"},
{n=71, title=surahNames[71], file="071-NOOH.MP3"}, {n=72, title=surahNames[72], file="072-AL-JINN.mp3"},
{n=73, title=surahNames[73], file="073-AL-MUZZAMMIL.mp3"}, {n=74, title=surahNames[74], file="074-AL-MUDDASSIR.mp3"},
{n=75, title=surahNames[75], file="075-AL-QIYAAMAH.mp3"}, {n=76, title=surahNames[76], file="076-AD-DAHR.mp3"},
{n=77, title=surahNames[77], file="077-AL-MURSALAAT.mp3"}, {n=78, title=surahNames[78], file="078-AN-NABA.mp3"},
{n=79, title=surahNames[79], file="079-AN-NAZIAAT.mp3"}, {n=80, title=surahNames[80], file="080-ABAS.MP3"},
{n=81, title=surahNames[81], file="081-AT-TAKWEER.mp3"}, {n=82, title=surahNames[82], file="082-AL-INFITAAR.mp3"},
{n=83, title=surahNames[83], file="083-AL-MUTTAFFIFEEN.mp3"}, {n=84, title=surahNames[84], file="084-AL-INSHIQAAQ.mp3"},
{n=85, title=surahNames[85], file="085-AL-BUROOJ.mp3"}, {n=86, title=surahNames[86], file="086-AT-TARIQ.mp3"},
{n=87, title=surahNames[87], file="087-AL-ALAA.mp3"}, {n=88, title=surahNames[88], file="088-AL-GHASHIAH.mp3"},
{n=89, title=surahNames[89], file="089-AL-FAJR.mp3"}, {n=90, title=surahNames[90], file="090-AL-BALAD.mp3"},
{n=91, title=surahNames[91], file="091-AS-SHAMS.mp3"}, {n=92, title=surahNames[92], file="092-AL-LAIL.mp3"},
{n=93, title=surahNames[93], file="093-AZ-ZUHAA.mp3"}, {n=94, title=surahNames[94], file="094-AL-INSHIRAH.mp3"},
{n=95, title=surahNames[95], file="095-AT-TEEN.mp3"}, {n=96, title=surahNames[96], file="096-AL-ALAQ.mp3"},
{n=97, title=surahNames[97], file="097-Al-QADR.mp3"}, {n=98, title=surahNames[98], file="098-AL-BAYYINAH.mp3"},
{n=99, title=surahNames[99], file="099-AZ-ZILZAAL.mp3"}, {n=100, title=surahNames[100], file="100-AL-ADIAAT.mp3"},
{n=101, title=surahNames[101], file="101-AL-QAARIAH.mp3"}, {n=102, title=surahNames[102], file="102AT-TAKASUR.mp3"},
{n=103, title=surahNames[103], file="103-AL-ASR.mp3"}, {n=104, title=surahNames[104], file="104-AL-HUMAZAH.mp3"},
{n=105, title=surahNames[105], file="105-AL-FEEL.mp3"}, {n=106, title=surahNames[106], file="106-QURESH.mp3"},
{n=107, title=surahNames[107], file="107-AL-MAAOON.mp3"}, {n=108, title=surahNames[108], file="108-AL-KAUSER.mp3"},
{n=109, title=surahNames[109], file="109-AL-KAFIROON.mp3"}, {n=110, title=surahNames[110], file="110-AN-NASR.mp3"},
{n=111, title=surahNames[111], file="111-AL-LAHAB.mp3"}, {n=112, title=surahNames[112], file="112-AL-IKHLAAS.mp3"},
{n=113, title=surahNames[113], file="113-AL-FALAQ.mp3"}, {n=114, title=surahNames[114], file="114-AN-NAAS.mp3"}
}
end
return _lazyCache.israrTafseer
end
M.buildIsrarTafseerUrl = function(t) return URLBASES.israrTafseer .. urlEncodeBytes(t.file) end
M.getIsrarTafseerLocal = function(t) return duaAudioDir .. "tafseer_israr_" .. t.n .. ".mp3" end
M.buildNawawiUrl = function(n) return URLBASES.nawawi .. string.format("nawawi%02d_64kb.mp3", n) end
M.getNawawiLocal = function(n) return duaAudioDir .. "nawawi_" .. n .. ".mp3" end
local bookmarksStr = prefs.getString("bookmarks", "")
local bookmarks = {}
if bookmarksStr ~= "" then for s in string.gmatch(bookmarksStr, "([^,]+)") do table.insert(bookmarks, tonumber(s)) end end
local pinnedStr = prefs.getString("pinnedSurahs", "")
local pinned = {}
if pinnedStr ~= "" then for s in string.gmatch(pinnedStr, "([^,]+)") do pinned[tonumber(s)] = true end end
local deletedStr = prefs.getString("deletedSurahs", "")
local deletedSurahs = {}
if deletedStr ~= "" then for s in string.gmatch(deletedStr, "([^,]+)") do deletedSurahs[tonumber(s)] = true end end
M.saveBookmarks = function() prefs.edit().putString("bookmarks", table.concat(bookmarks, ",")).apply() end
M.savePinned = function() local arr = {} for k,v in pairs(pinned) do if v then table.insert(arr, k) end end prefs.edit().putString("pinnedSurahs", table.concat(arr, ",")).apply() end
M.saveDeleted = function() local arr = {} for k,v in pairs(deletedSurahs) do if v then table.insert(arr, k) end end prefs.edit().putString("deletedSurahs", table.concat(arr, ",")).apply() end
M.saveLastPlayed = function(s_index, r_index)
local rName = reciters[r_index] and reciters[r_index].name or ""
prefs.edit().putInt("lastSurah", s_index).putString("lastReciterName", rName).apply()
lastPlayedSurah = s_index
lastPlayedReciter = r_index
end
M.saveActiveTasbeehState = function() prefs.edit().putInt("activeCount", tasbeehCount).putInt("activeTarget", tasbeehTarget).putInt("activeWazeefa", currentWazeefaIndex).putBoolean("tasbeehBeep", tasbeehBeepEnabled).putBoolean("tasbeehVibrate", tasbeehVibrateEnabled).apply() end
M.playBeep = function() pcall(function() local r=import("android.media.RingtoneManager") local uri=r.getDefaultUri(r.TYPE_NOTIFICATION) r.getRingtone(activity,uri).play() end) end
M.doVibrate = function(ms) pcall(function() activity.getSystemService(Context.VIBRATOR_SERVICE).vibrate(ms) end) end
M.hideKeyboard = function(view) pcall(function() activity.getSystemService(Context.INPUT_METHOD_SERVICE).hideSoftInputFromWindow(view.getWindowToken(), 0) end) end
M.showPlaybackNotification = function(title, text) pcall(function() local nm = activity.getSystemService(Context.NOTIFICATION_SERVICE) if Build.VERSION.SDK_INT >= 26 then nm.createNotificationChannel(NotificationChannel("quran_audio_v2", "Quran Playback", NotificationManager.IMPORTANCE_DEFAULT)) end local builder = Notification.Builder(activity) if Build.VERSION.SDK_INT >= 26 then builder = Notification.Builder(activity, "quran_audio_v2") end
local piFlags = PendingIntent.FLAG_UPDATE_CURRENT
if Build.VERSION.SDK_INT >= 23 then pcall(function() piFlags = piFlags + PendingIntent.FLAG_IMMUTABLE end) end
local ciOk, ciErr = pcall(function()
local pi = PendingIntent.getActivity(activity, 0, Intent(activity, activity.getClass()), piFlags)
builder.setContentIntent(pi)
end)
local isPlayingNow = (mp and mp.isPlaying()) or (duaMp and duaMp.isPlaying())
local actOk, actErr = pcall(function()
local prevPI = PendingIntent.getBroadcast(activity, 2, Intent("quran_majeed_prev"), piFlags)
local playPausePI = PendingIntent.getBroadcast(activity, 1, Intent("quran_majeed_playpause"), piFlags)
local nextPI = PendingIntent.getBroadcast(activity, 3, Intent("quran_majeed_next"), piFlags)
builder.addAction(android.R.drawable.ic_media_previous, "Previous", prevPI)
builder.addAction(isPlayingNow and android.R.drawable.ic_media_pause or android.R.drawable.ic_media_play, isPlayingNow and "Pause" or "Play", playPausePI)
builder.addAction(android.R.drawable.ic_media_next, "Next", nextPI)
end)
if not actOk and not PS.notifActionErrorShown then
PS.notifActionErrorShown = true
Toast.makeText(activity, "Notification controls add nahi ho sakay - error: " .. tostring(actErr), 1).show()
end
builder.setContentTitle(title).setContentText(text).setSmallIcon(android.R.drawable.ic_media_play).setOngoing(true)
nm.notify(1, builder.build()) end) end
M.cancelNotification = function() pcall(function() activity.getSystemService(Context.NOTIFICATION_SERVICE).cancel(1) end) end
M.startSleepTimer = function()
targetSleepTime = 0
if sleepTimerMinutes > 0 and mp and mp.isPlaying() then
targetSleepTime = os.time() + (sleepTimerMinutes * 60)
end
end
M.stopPlayer = function(onDone)
if updateTask then handler.removeCallbacks(updateTask) end
targetSleepTime = 0
local oldMp = mp
local oldDuaMp = duaMp
mp = nil
duaMp = nil
M.cancelNotification()
if oldMp or oldDuaMp then
Thread(Runnable{run=function()
if oldMp then pcall(function() oldMp.stop() end) pcall(function() oldMp.release() end) end
if oldDuaMp then pcall(function() oldDuaMp.stop() end) pcall(function() oldDuaMp.release() end) end
if onDone then handler.post(Runnable{run=function() pcall(onDone) end}) end
end}).start()
elseif onDone then
onDone()
end
end
function V25.downloadAudioFile(url, cachePath, label)
local ok, err = pcall(function()
local req = DownloadManager.Request(Uri.parse(url))
req.setTitle(label)
req.setDescription("Quran Majeed - manual download")
req.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
local root = File(publicDownloadsRoot).getAbsolutePath()
local destination = File(cachePath).getAbsolutePath()
if destination:sub(1, #root + 1) ~= root .. "/" then
req.setDestinationUri(Uri.fromFile(File(cachePath)))
else
local relative = destination:sub(#root + 2)
local parent = File(cachePath).getParentFile()
if parent and not parent.exists() then parent.mkdirs() end
req.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, relative)
end
activity.getSystemService(Context.DOWNLOAD_SERVICE).enqueue(req)
end)
if ok then
Toast.makeText(activity, "Download shuru - khatam hone par is screen par Play karein (offline chalega).", 1).show()
else
showErrorDialog("Download Error - " .. tostring(label), err)
end
end
function V25.showStreamFailure(label, url, cachePath, retryFn)
local msg = "Online stream nahi chal saki.\n\n" .. tostring(label) .. "\n" .. tostring(url) ..
"\n\nv3.1 mein AUTO-DOWNLOAD band kar diya gaya hai (wahi phone ko hang kar raha tha). Ab aap khud chunein:"
local ok = pcall(function()
AlertDialog.Builder(activity)
.setTitle("⚠ Online stream fail")
.setMessage(msg)
.setPositiveButton("Retry online", {onClick=function() safeRun("Retry stream", retryFn) end})
.setNeutralButton("Download", {onClick=function() safeRun("Download audio", function() V25.downloadAudioFile(url, cachePath, label) end) end})
.setNegativeButton("Cancel", nil)
.show()
end)
if not ok then Toast.makeText(activity, "Online stream fail: " .. tostring(label), 1).show() end
end
M.playReliable = function(urls, cachePath, label, refreshFn, onComplete, startAt, endAt)
local urlList = (type(urls) == "table") and urls or {urls}
local tryStream
if not PS then PS = {} end
PS.duaWanted = true
PS.duaState = "loading"
if updateTask then pcall(function() handler.removeCallbacks(updateTask) end) end
if V25.clipTask then pcall(function() handler.removeCallbacks(V25.clipTask) end) end
local function startClipWatcher(p)
if not (endAt and endAt > 0) then return end
local endMs = math.floor(endAt * 1000)
local startMs = math.floor((startAt or 0) * 1000)
V25.clipTask = Runnable({run = function()
pcall(function()
if p and p.isPlaying() and p.getCurrentPosition() >= endMs then
p.pause() p.seekTo(startMs)
if onComplete then onComplete() elseif refreshFn then refreshFn() end
return
end
end)
handler.postDelayed(V25.clipTask, 800)
end})
handler.postDelayed(V25.clipTask, 800)
end
M.stopPlayer(function()
local urlIdx = 1
tryStream = function()
local url = urlList[urlIdx]
Toast.makeText(activity, "Loading: " .. label .. "...", 1).show()
if not PS.duaWanted and PS.duaState ~= "idle" then return end
PS.duaGen = (PS.duaGen or 0) + 1
local myGen = PS.duaGen
duaMp = MediaPlayer()
pcall(function() duaMp.setAudioStreamType(AudioManager.STREAM_MUSIC) end)
pcall(function() duaMp.setWakeMode(activity, PowerManager.PARTIAL_WAKE_LOCK) end)
local streamFailed = false
local dsOk = pcall(function() duaMp.setDataSource(url) end)
if not dsOk then
showErrorDialog("Audio Error - " .. tostring(label), "Audio source set nahi ho saka (setDataSource fail).\n\nLabel: " .. tostring(label) .. "\nURL: " .. tostring(url))
return
end
duaMp.setOnErrorListener(MediaPlayer.OnErrorListener{onError=function(p,w,e)
if PS.duaGen ~= myGen then return true end
if not PS.duaWanted then return true end
if streamFailed then return true end
streamFailed = true
if urlIdx < #urlList then
urlIdx = urlIdx + 1
pcall(function() duaMp.release() end)
tryStream()
return true
end
V25.showStreamFailure(label, url, cachePath, tryStream)
return true
end})
duaMp.setOnPreparedListener(MediaPlayer.OnPreparedListener{onPrepared=function(p)
if PS.duaGen ~= myGen then pcall(function() p.release() end) duaMp = nil return end
if not PS.duaWanted then pcall(function() p.pause() end) return end
PS.duaState = "playing"
local okp, errp = pcall(function()
applyPlaybackSpeed(p)
if startAt and startAt > 0 then p.seekTo(math.floor(startAt * 1000)) end
p.start()
startClipWatcher(p)
end)
if not okp then showErrorDialog("Play Error - " .. tostring(label), errp) end
Toast.makeText(activity, "Playing: " .. label, 0).show()
if refreshFn then refreshFn() end
end})
duaMp.setOnCompletionListener(MediaPlayer.OnCompletionListener{onCompletion=function() if V25.clipTask then pcall(function() handler.removeCallbacks(V25.clipTask) end) V25.clipTask = nil end if onComplete then onComplete() elseif refreshFn then refreshFn() end end})
duaMp.prepareAsync()
end
if File(cachePath).exists() and File(cachePath).length() >= 1000 then
local fileSize = File(cachePath).length()
local ok = pcall(function()
duaMp = MediaPlayer()
pcall(function() duaMp.setAudioStreamType(AudioManager.STREAM_MUSIC) end)
pcall(function() duaMp.setWakeMode(activity, PowerManager.PARTIAL_WAKE_LOCK) end)
duaMp.setDataSource(cachePath)
duaMp.setOnErrorListener(MediaPlayer.OnErrorListener{onError=function(p,w,e)
Toast.makeText(activity, "Cached file (size: " .. fileSize .. " bytes) kharab nikli, online try kar rahe hain...", 0).show()
pcall(function() File(cachePath).delete() end)
pcall(function() duaMp.release() end)
duaMp = nil
tryStream()
return true
end})
duaMp.setOnPreparedListener(MediaPlayer.OnPreparedListener{onPrepared=function(p)
local okp, errp = pcall(function()
applyPlaybackSpeed(p)
if startAt and startAt > 0 then p.seekTo(math.floor(startAt * 1000)) end
p.start()
startClipWatcher(p)
end)
if not okp then showErrorDialog("Play Error (offline) - " .. tostring(label), errp) end
Toast.makeText(activity, "Playing (offline): " .. label, 0).show()
if refreshFn then refreshFn() end
end})
duaMp.setOnCompletionListener(MediaPlayer.OnCompletionListener{onCompletion=function() if V25.clipTask then pcall(function() handler.removeCallbacks(V25.clipTask) end) V25.clipTask = nil end if onComplete then onComplete() elseif refreshFn then refreshFn() end end})
duaMp.prepareAsync()
end)
if ok then return end
pcall(function() if duaMp then duaMp.release() end end)
duaMp = nil
pcall(function() File(cachePath).delete() end)
Toast.makeText(activity, "Cached file mein masla tha (size: " .. fileSize .. " bytes), dobara try kar rahe hain...", 0).show()
end
tryStream()
end)
end
local playerReady = false
local playIntentPending = false
local function togglePlayPause()
if PS.externalPlayback then
if PS.externalPreparing then
PS.externalPausePending=not PS.externalPausePending
if btnPlayPause then btnPlayPause.setText("Loading...") end
return
end
if not duaMp then showPlayer(currentIndex); return end
pcall(function()
if duaMp.isPlaying() then duaMp.pause(); isPaused=true; if btnPlayPause then btnPlayPause.setText("▶ "..tr("Play")) end
else
if duaMp.getDuration()>0 and duaMp.getCurrentPosition()>=duaMp.getDuration()-500 then duaMp.seekTo(0) end
duaMp.start(); isPaused=false; if btnPlayPause then btnPlayPause.setText("⏸ "..tr("Pause")) end
M.startSleepTimer()
end
end)
return
end
if not mp then return end
if not playerReady then
playIntentPending = true
pcall(function() if btnPlayPause then btnPlayPause.setText(tr("Loading...")) end end)
return
end
pcall(function()
if mp.isPlaying() then
mp.pause() isPaused=true
if btnPlayPause then btnPlayPause.setText("▶ " .. tr("Play")) end
targetSleepTime = 0
if surahNames[currentIndex] then M.showPlaybackNotification(surahNames[currentIndex], "Reciter: " .. (reciters[currentReciter] and reciters[currentReciter].name or "")) end
else
mp.start() isPaused=false
if btnPlayPause then btnPlayPause.setText("⏸ " .. tr("Pause")) end
M.startSleepTimer()
if surahNames[currentIndex] then M.showPlaybackNotification(surahNames[currentIndex], "Reciter: " .. (reciters[currentReciter] and reciters[currentReciter].name or "")) end
end
end)
end
local function seekForward()
local p=(PS.externalPlayback and duaMp) or mp
if p then pcall(function() local n=p.getCurrentPosition()+(seekSeconds*1000); if n>p.getDuration() then n=p.getDuration() end; p.seekTo(n); Toast.makeText(activity,"Forward "..seekSeconds.."s",0).show() end) end
end
local function seekRewind()
local p=(PS.externalPlayback and duaMp) or mp
if p then pcall(function() local n=p.getCurrentPosition()-(seekSeconds*1000); if n<0 then n=0 end; p.seekTo(n); Toast.makeText(activity,"Rewind "..seekSeconds.."s",0).show() end) end
end
local showHome, showSettings, showAbout, showFeedback, showSurahList, showPlayer, showTasbeeh, showBookmarksScreen, showNamesOfAllah, showReadingMode, showDailyDuas, showPara, showParaSurahs, playNextSurah, playPrevSurah, downloadSurah, confirmDelete, showAzan
M.bottomTabs = function(activeTab)
local function tabColor(tab) return (activeTab == tab) and appColorStr or "#00000000" end
local function tabTextColor(tab) return (activeTab == tab) and -1 or -12303292 end
return {LinearLayout, orientation=0, layout_width=-1, backgroundColor="#1A000000",
{Button, text="Home", textSize="13sp", layout_weight=1, backgroundColor=tabColor("home"), textColor=tabTextColor("home"), contentDescription="Home tab", onClick=function() safeRun("showHome", showHome) end},
{Button, text="Quran", textSize="13sp", layout_weight=1, backgroundColor=tabColor("quran"), textColor=tabTextColor("quran"), contentDescription="Quran tab", onClick=function() safeRun("showSurahList", showSurahList) end},
{Button, text="Duas", textSize="13sp", layout_weight=1, backgroundColor=tabColor("duas"), textColor=tabTextColor("duas"), contentDescription="Duas tab", onClick=function() safeRun("showDailyDuas", showDailyDuas) end},
{Button, text="More", textSize="13sp", layout_weight=1, backgroundColor=tabColor("more"), textColor=tabTextColor("more"), contentDescription="More tab", onClick=function() safeRun("showMore", showMore) end}
}
end
M.moreSubTabs = function(activeTab)
local function tabColor(tab) return (activeTab == tab) and appColorStr or "#00000000" end
local function tabTextColor(tab) return (activeTab == tab) and -1 or -12303292 end
return {HorizontalScrollView, layout_width=-1, backgroundColor="#1A000000",
{LinearLayout, orientation=0, layout_width="wrap_content",
{Button, text="Para", textSize="12sp", layout_width="72dp", backgroundColor=tabColor("para"), textColor=tabTextColor("para"), contentDescription="30 Para tab", onClick=function() safeRun("showPara", showPara) end},
{Button, text="Tasbeeh", textSize="12sp", layout_width="72dp", backgroundColor=tabColor("tasbeeh"), textColor=tabTextColor("tasbeeh"), contentDescription="Digital Tasbeeh tab", onClick=function() safeRun("showTasbeeh", showTasbeeh) end},
{Button, text="Bookmarks", textSize="12sp", layout_width="72dp", backgroundColor=tabColor("bookmarks"), textColor=tabTextColor("bookmarks"), contentDescription="Bookmarks tab", onClick=function() safeRun("showBookmarksScreen", showBookmarksScreen) end},
{Button, text="Names", textSize="12sp", layout_width="72dp", backgroundColor=tabColor("names"), textColor=tabTextColor("names"), contentDescription="99 Names tab", onClick=function() safeRun("showNamesOfAllah", showNamesOfAllah) end},
{Button, text="Prophet Names", textSize="12sp", layout_width="72dp", backgroundColor=tabColor("asmanabi"), textColor=tabTextColor("asmanabi"), contentDescription="Blessed Names tab", onClick=function() safeRun("showAsmaNabi", showAsmaNabi) end},
{Button, text="Full Quran", textSize="12sp", layout_width="72dp", backgroundColor=tabColor("fullquran"), textColor=tabTextColor("fullquran"), contentDescription="Poori Quran Continuous tab", onClick=function() safeRun("showFullQuranScreen", showFullQuranScreen) end},
{Button, text="Hadith", textSize="12sp", layout_width="72dp", backgroundColor=tabColor("hadith"), textColor=tabTextColor("hadith"), contentDescription="Hadith tab", onClick=function() safeRun("showHadithScreen", showHadithScreen) end},
{Button, text="Tafseer 2", textSize="12sp", layout_width="72dp", backgroundColor=tabColor("israr"), textColor=tabTextColor("israr"), contentDescription="Tafseer Israr Ahmad tab", onClick=function() safeRun("showIsrarTafseerScreen", showIsrarTafseerScreen) end},
{Button, text="40 Hadith", textSize="12sp", layout_width="72dp", backgroundColor=tabColor("nawawi"), textColor=tabTextColor("nawawi"), contentDescription="40 Hadith Nawawi tab", onClick=function() safeRun("showNawawiScreen", showNawawiScreen) end},
{Button, text="Adhan", textSize="12sp", layout_width="72dp", backgroundColor=tabColor("azan"), textColor=tabTextColor("azan"), contentDescription="Adhan audio tab", onClick=function() safeRun("showAzan", showAzan) end},
{Button, text="Menu", textSize="12sp", layout_width="72dp", backgroundColor=tabColor("menu"), textColor=tabTextColor("menu"), contentDescription="Menu tab", onClick=function() safeRun("showSettings", showSettings) end},
{Button, text="Home", textSize="12sp", layout_width="72dp", backgroundColor=tabColor("home"), textColor=tabTextColor("home"), contentDescription="Back to Home tab", onClick=function() safeRun("showHome", showHome) end}
}
}
end
local duaPlayerIndex = 1
local audioDuasCache = {}
M.buildAudioDuasList = function()
audioDuasCache = {}
for _, d in ipairs(dailyDuas()) do if d.audio ~= "" then table.insert(audioDuasCache,d) end end
return audioDuasCache
end
M.buildSearchIndex = function()
local idx = {}
for i, name in ipairs(surahNames) do
table.insert(idx, {label="Surah: " .. name, action=function()
AlertDialog.Builder(activity).setTitle(name).setItems({"Play Surah", "Ayat-ba-Ayat Mode", "Ruku Mode", "Word-by-Word (Hifz)"}, {onClick=function(d, w)
if w == 0 then showPlayer(i)
elseif w == 1 then showAyahByAyah(i)
elseif w == 2 then showRukuMode(i)
elseif w == 3 then showWbwStartDialog(i) end
end}).show()
end})
end
for i, n in ipairs(paraNames) do
table.insert(idx, {label="Para " .. i .. ": " .. n, action=function()
showParaSurahs(i)
end})
end
for _, lang in ipairs({"Off", "Urdu", "Hindi", "Punjabi", "English", "Sindhi", "English (Mishary)", "Bengali", "French", "Pashto", "Farsi", "Urdu (Waheed Zafar)", "Urdu (Shakir Qasmi)"}) do
table.insert(idx, {label="Tarjuma: " .. lang, searchText=lang, action=function()
M.saveTranslationMode(lang)
Toast.makeText(activity, "Tarjuma set to " .. lang, 1).show()
showSurahList()
end})
end
for i, r in ipairs(reciters) do
local rName = r.name
table.insert(idx, {label="Reciter: " .. rName, searchText=rName, action=function()
currentReciter = i
Toast.makeText(activity, "Reciter set to " .. rName .. " - ab Surah select karein", 1).show()
showSurahList()
end})
end
for _, d in ipairs(dailyDuas()) do
if d.audio ~= "" then
table.insert(idx, {label="Dua (Audio): " .. d.title, searchText=(d.title.." "..tostring(d.en or "").." "..tostring(d.ur or "").." "..tostring(d.ar or "")), action=function()
M.buildAudioDuasList()
for ai, ad in ipairs(audioDuasCache) do if ad == d then showDuaPlayer(ai) return end end
end})
else
table.insert(idx, {label="Dua (Text): " .. d.title, searchText=(d.title.." "..tostring(d.en or "").." "..tostring(d.ur or "").." "..tostring(d.ar or "")), action=function()
local dlgBody = d.ar .. "\n\n" .. d.ur .. ((d.link and d.link ~= "") and ("\n\n" .. d.link) or "")
local dlg = AlertDialog.Builder(activity).setTitle(d.title).setMessage(dlgBody)
if d.link and d.link ~= "" then dlg.setNeutralButton("▶️ Online sunnein", {onClick=function() safeRun("Open source page", M.openLinkAndClose, d.link) end}) end
dlg.setPositiveButton("Copy", {onClick=function() V25.copyTextToClipboard(dlgBody) end})
dlg.setNegativeButton("Cancel", nil).show()
end})
end
end
return idx
end
M.buildAyahSearchResult = function(query)
local numPart = query:match("(%d+)%s*$")
if not numPart then return nil end
local ayahNum = tonumber(numPart)
local beforeNum = query:sub(1, #query - #numPart):gsub("%s+$", "")
if beforeNum == "" then return nil end
local surahIdx = tonumber(beforeNum)
if not surahIdx then
for i, name in ipairs(surahNames) do
if name:lower():find(beforeNum, 1, true) then surahIdx = i break end
end
end
if not surahIdx or not surahNames[surahIdx] then return nil end
local mx = surahAyahCounts[surahIdx] or 1
if ayahNum < 1 or ayahNum > mx then return nil end
return {label="Play: " .. surahNames[surahIdx] .. " - Ayat " .. ayahNum, action=function()
showAyahByAyah(surahIdx, ayahNum)
end}
end
function showHome()
screen = "home"
M.stopPlayer()
activity.getWindow().clearFlags(128)
local bgColor, textColor = M.getThemeColors()
local spot = M.pickSpotlight()
local searchIndex = nil
if lastPrayerFetchDate ~= M.todayDateString() and savedCity ~= "" and savedCountry ~= "" then
M.fetchPrayerTimes(savedCity, savedCountry, function(ok)
if ok and screen == "home" then showHome() end
end)
end
activity.setContentView(loadlayout{
LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor, focusable=true, focusableInTouchMode=true,
{TextView, text="Quran Majeed v3.1", textSize="24sp", typeface=Typeface.DEFAULT_BOLD, gravity="center", padding="10dp", textColor=appColorStr, contentDescription="Quran Majeed, version 3.1"},
{LinearLayout, orientation=0, layout_width=-1, padding="10dp", gravity="center_vertical",
{EditText, id="etHomeSearch", hint="Search Surah, Reciter, Dua (Arabic/Urdu/English)...", layout_weight=1, singleLine=true, textColor=textColor, hintTextColor="#888888", contentDescription="Search Quran, duas and translations"},
{Button, id="btnHomeSearch", text="Search", textSize="12sp", layout_marginLeft="4dp", backgroundColor=appColorStr, textColor=-1, contentDescription="Search"},
{Button, id="btnVoiceSearch", text="🎙", textSize="16sp", layout_marginLeft="4dp", backgroundColor="#1565C0", textColor=-1, contentDescription="Start voice search"}
},
{Spinner, id="homeSearchFilter", layout_width=-1, layout_marginLeft="10dp", layout_marginRight="10dp", contentDescription="Filter search results by type"},
{TextView, id="txtHomeSearchStatus", text="", textSize="11sp", textColor="#777777", padding="4dp"},
{ListView, id="homeSearchResults", layout_width=-1, layout_height="260dp"},
{ScrollView, id="homeScroll", layout_width=-1, layout_height=0, layout_weight=1,
{LinearLayout, orientation=1, gravity="center_horizontal", padding="20dp", layout_width=-1, layout_height=-2,
{LinearLayout, orientation=1, layout_width=-1, padding="15dp", layout_marginBottom="15dp", backgroundColor="#1A000000",
{LinearLayout, orientation=0, layout_width=-1, gravity="center_vertical", layout_marginBottom="6dp",
{TextView, text=os.date("%d %B %Y (%A)"), textSize="12sp", textColor=textColor, layout_weight=1},
{TextView, text="🔋 " .. (M.currentBatteryPercent() >= 0 and (M.currentBatteryPercent() .. "%") or "?"), textSize="12sp", textColor=textColor}
},
{LinearLayout, orientation=1, layout_width=-1, gravity="center_horizontal", layout_marginBottom="10dp",
{TextView, id="txtIslamicDateUrdu", text=(function() local ok, r = pcall(V25.islamicLineUrdu) if ok and r then return r end return "" end)(), textSize="14sp", typeface=Typeface.DEFAULT_BOLD, textColor=textColor, gravity="center", layout_marginBottom="2dp"},
{TextView, id="txtIslamicDate", text=(function() local ok, r = pcall(V25.islamicLineRoman) if ok and r then return r end return "Islamic Calendar" end)(), textSize="12sp", textColor=textColor, gravity="center", layout_marginBottom="2dp"},
{TextView, text=(function() local ok, pd, pm, py = pcall(M.getPunjabiDate) if ok and pd then return "Punjabi: " .. tostring(pd) .. " " .. tostring(pm) .. ", " .. tostring(py) .. " Samat" end return "Punjabi" end)(), textSize="12sp", textColor=textColor, gravity="center"}
},
(spot.kind=="ayah") and {LinearLayout, orientation=1,
{TextView, text=tr("Ayat of the Day"), textSize="16sp", typeface=Typeface.DEFAULT_BOLD, textColor=appColorStr, layout_marginBottom="5dp"},
{TextView, text=spot.data.ar, textSize="22sp", typeface=Typeface.DEFAULT_BOLD, textColor=textColor, gravity="right", layout_marginBottom="5dp"},
{TextView, text=spot.data.ur, textSize="16sp", textColor=textColor, gravity="right", layout_marginBottom="5dp"},
{TextView, text=spot.data.ref, textSize="12sp", textColor="#777777", gravity="left"}
} or (spot.kind=="allahname") and {LinearLayout, orientation=1,
{TextView, text="Name of Allah", textSize="16sp", typeface=Typeface.DEFAULT_BOLD, textColor=appColorStr, layout_marginBottom="5dp"},
{TextView, text=spot.data.ar, textSize="26sp", typeface=Typeface.DEFAULT_BOLD, textColor=textColor, gravity="center", layout_marginBottom="5dp"},
{TextView, text=spot.data.ro .. " - " .. spot.data.ur, textSize="14sp", textColor=textColor, gravity="center"}
} or (spot.kind=="nabiname") and {LinearLayout, orientation=1,
{TextView, text="Blessed Name of Prophet", textSize="16sp", typeface=Typeface.DEFAULT_BOLD, textColor=appColorStr, layout_marginBottom="5dp"},
{TextView, text=spot.data.ar, textSize="26sp", typeface=Typeface.DEFAULT_BOLD, textColor=textColor, gravity="center", layout_marginBottom="5dp"},
{TextView, text=spot.data.ro .. " - " .. spot.data.ur, textSize="14sp", textColor=textColor, gravity="center"}
} or {LinearLayout, orientation=1,
{TextView, text="Surah Spotlight", textSize="16sp", typeface=Typeface.DEFAULT_BOLD, textColor=appColorStr, layout_marginBottom="5dp"},
{TextView, text="Surah " .. spot.data, textSize="22sp", typeface=Typeface.DEFAULT_BOLD, textColor=textColor, gravity="center"}
}
},
{LinearLayout, orientation=1, layout_width=-1, padding="15dp", layout_marginBottom="20dp", backgroundColor="#1A000000",
{LinearLayout, orientation=0, layout_width=-1, gravity="center_vertical", layout_marginBottom="10dp",
{TextView, text=tr("Prayer Times") .. " ("..savedCity..")", textSize="16sp", typeface=Typeface.DEFAULT_BOLD, textColor=appColorStr, layout_weight=1},
{Button, text=tr("Update Location"), textSize="12sp", backgroundColor="#1976D2", textColor=-1, onClick=function()
local inputCity = EditText(activity) inputCity.setHint("City (e.g. Lahore, Dubai)") inputCity.setText(savedCity)
local inputCountry = EditText(activity) inputCountry.setHint("Country (e.g. Pakistan)") inputCountry.setText(savedCountry)
local dLayout = LinearLayout(activity) dLayout.setOrientation(LinearLayout.VERTICAL) dLayout.setPadding(30,20,30,20) dLayout.addView(inputCity) dLayout.addView(inputCountry)
AlertDialog.Builder(activity).setTitle(tr("Update Location")).setView(dLayout).setPositiveButton("Fetch Times", {onClick=function()
local c = inputCity.getText().toString()
local cntry = inputCountry.getText().toString()
if c ~= "" and cntry ~= "" then
Toast.makeText(activity, "Fetching exact times...", 1).show()
M.fetchPrayerTimes(c, cntry, function(ok)
if ok then
showHome() Toast.makeText(activity, "Updated successfully!", 0).show()
else
Toast.makeText(activity, "City not found ya network error.", 0).show()
end
end)
end
end}).setNegativeButton("Cancel", nil).show()
end}
},
{LinearLayout, orientation=0, layout_width=-1, gravity="center", layout_marginBottom="6dp",
{TextView, text="Fajr\n"..to12Hour(prayerFajr), textSize="13sp", textColor=textColor, layout_weight=1, gravity="center"},
{TextView, text="Sunrise\n"..to12Hour(prayerSunrise), textSize="13sp", textColor=textColor, layout_weight=1, gravity="center"},
{TextView, text="Dhuhr\n"..to12Hour(prayerDhuhr), textSize="13sp", textColor=textColor, layout_weight=1, gravity="center"}
},
{LinearLayout, orientation=0, layout_width=-1, gravity="center", layout_marginBottom="10dp",
{TextView, text="Asr\n"..to12Hour(prayerAsr), textSize="13sp", textColor=textColor, layout_weight=1, gravity="center"},
{TextView, text="Maghrib\n"..to12Hour(prayerMaghrib), textSize="13sp", textColor=textColor, layout_weight=1, gravity="center"},
{TextView, text="Isha\n"..to12Hour(prayerIsha), textSize="13sp", textColor=textColor, layout_weight=1, gravity="center"}
},
{TextView, text="Tahajjud Time: " .. calcTahajjud(prayerMaghrib, prayerFajr), textSize="14sp", typeface=Typeface.DEFAULT_BOLD, textColor="#8E24AA", gravity="center"}
}
}},
M.bottomTabs("home")
})
M.applyWallpaper(mainLayout, bgColor)
pcall(function()
if etHomeSearch then
pcall(function() etHomeSearch.setHint("Search: Surah, Dua, Kalma, Kitaab, Episode...") end)
pcall(function() etHomeSearch.setOnLongClickListener(function() safeRun("showAdvancedSearch", showAdvancedSearch) return true end) end)
pcall(function()
local par = etHomeSearch.getParent()
if par then
local ab = Button(activity)
ab.setText("Advanced")
ab.setTextSize(12)
local tc = V25.safeTextColor(textColor)
if tc then pcall(function() ab.setTextColor(tc) end) end
par.addView(ab)
ab.setOnClickListener(function() safeRun("showAdvancedSearch", showAdvancedSearch) end)
end
end)
end
end)
etHomeSearch.clearFocus()
pcall(function() mainLayout.requestFocus() end)
M.hideKeyboard(etHomeSearch)
handler.postDelayed(function()
pcall(function() etHomeSearch.clearFocus() mainLayout.requestFocus() M.hideKeyboard(etHomeSearch) end)
end, 200)
local function runHomeSearch()
local q = tostring(etHomeSearch.getText()):lower()
if q == "" then
homeSearchResults.setAdapter(ArrayAdapter(activity, android.R.layout.simple_list_item_1, {}))
pcall(function() txtHomeSearchStatus.setText("") end)
else
if not searchIndex then searchIndex = M.buildSearchIndex() end
local matches = {}
local labels = {}
local ayahResult = M.buildAyahSearchResult(q)
if ayahResult then
table.insert(matches, ayahResult)
table.insert(labels, ayahResult.label)
end
local function fuzzyMatch(hay, needle)
hay=tostring(hay or ""):lower()
needle=tostring(needle or ""):lower()
if needle=="" then return true end
if hay:find(needle,1,true) then return true end
local j=1
for i=1,#hay do
if hay:sub(i,i)==needle:sub(j,j) then
j=j+1
if j>#needle then return true end
end
end
return false
end
local filterNames={"All","Surahs","Reciters","Translations","Duas"}
local filter=filterNames[(homeSearchFilter.getSelectedItemPosition() or 0)+1] or "All"
for _, item in ipairs(searchIndex) do
local label=item.label or ""
local allowed=(filter=="All") or
(filter=="Surahs" and (label:find("^Surah:") or label:find("^Play:"))) or
(filter=="Reciters" and label:find("^Reciter:")) or
(filter=="Translations" and label:find("^Tarjuma:")) or
(filter=="Duas" and label:find("^Dua "))
if allowed and fuzzyMatch(item.searchText or label,q) then
table.insert(matches,item) table.insert(labels,label)
if #matches>=100 then break end
end
end
pcall(function() txtHomeSearchStatus.setText(#matches .. " result(s) - tap one to play/select it") end)
homeSearchResults.setAdapter(ArrayAdapter(activity, android.R.layout.simple_list_item_1, labels))
homeSearchResults.onItemClick = function(l, v, p, i)
M.hideKeyboard(etHomeSearch)
if matches[i+1] then matches[i+1].action() end
end
end
end
local searchFilters={"All", "Surahs", "Reciters", "Translations", "Duas"}
homeSearchFilter.setAdapter(ArrayAdapter(activity, android.R.layout.simple_spinner_dropdown_item, searchFilters))
homeSearchFilter.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{onItemSelected=function() runHomeSearch() end})
etHomeSearch.addTextChangedListener(TextWatcher{onTextChanged=function(c) runHomeSearch() end})
btnHomeSearch.onClick = function() M.hideKeyboard(etHomeSearch) runHomeSearch() end
btnVoiceSearch.onClick = function()
local ok, err = pcall(function()
local i=Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
i.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
i.putExtra(RecognizerIntent.EXTRA_PROMPT, "Speak a Surah, dua, reciter, or translation")
activity.startActivityForResult(i, 2606)
end)
if not ok then Toast.makeText(activity,"Speech recognition service is not available on this device.",1).show() end
end
V25.startDateTick()
end
function showAzanPlayer(trackIndex)
if trackIndex<1 or trackIndex>#AZAN_TRACKS then return end
screen="azanplayer"
M.stopPlayer()
local track=AZAN_TRACKS[trackIndex]
local path=M.getAzanLocalPath(trackIndex)
local downloaded=File(path).exists() and File(path).length()>1000
local bgColor,textColor=M.getThemeColors()
activity.setContentView(loadlayout{
LinearLayout,id="mainLayout",orientation=1,padding="18dp",layout_width=-1,layout_height=-1,gravity="center",backgroundColor=bgColor,
{LinearLayout,orientation=0,layout_width=-1,gravity="center_vertical",
{Button,text="Back",contentDescription="Back to Adhan audio list",onClick=function() safeRun("showAzan", showAzan) end},
{TextView,text="Adhan Player",textSize="20sp",typeface=Typeface.DEFAULT_BOLD,textColor=appColorStr,layout_marginLeft="10dp"}
},
{TextView,id="azanPlayerState",text=downloaded and "Offline playback" or "Online streaming",textSize="13sp",textColor=appColorStr,layout_marginTop="14dp",gravity="center"},
{TextView,text=track.name,textSize="22sp",typeface=Typeface.DEFAULT_BOLD,textColor=appColorStr,layout_marginTop="8dp",gravity="center"},
{TextView,text=savedCity..", "..savedCountry,textSize="13sp",textColor=textColor,layout_marginTop="4dp",gravity="center"},
{SeekBar,id="azanSeekBar",layout_width=-1,layout_marginTop="20dp"},
{LinearLayout,orientation=0,layout_width=-1,gravity="center",layout_marginBottom="8dp",
{TextView,id="azanCurrentTime",text="00:00",layout_weight=1,gravity="center",textColor=textColor},
{TextView,id="azanTotalTime",text="00:00",layout_weight=1,gravity="center",textColor=textColor}
},
{LinearLayout,orientation=0,layout_width=-1,gravity="center",
{Button,text="⏮",layout_weight=1,contentDescription="Previous Adhan",onClick=function() if trackIndex>1 then showAzanPlayer(trackIndex-1) end end},
{Button,text="⏪ "..seekSeconds.."s",layout_weight=1.3,contentDescription="Rewind Adhan",onClick=function() if duaMp then pcall(function() local n=duaMp.getCurrentPosition()-seekSeconds*1000 duaMp.seekTo(math.max(0,n)) end) end end},
{Button,id="btnAzanPlay",text="▶ Play",layout_weight=1.5,contentDescription="Play or pause Adhan",onClick=function()
if duaMp then pcall(function() if duaMp.isPlaying() then duaMp.pause() btnAzanPlay.setText("▶ Play") else duaMp.start() btnAzanPlay.setText("⏸ Pause") end end)
else
btnAzanPlay.setText("Loading...")
local u=track.url
M.playReliable(u,path,track.name,nil,function() pcall(function() if btnAzanPlay then btnAzanPlay.setText("▶ Play") end end) end)
end
end},
{Button,text=seekSeconds.."s ⏩",layout_weight=1.3,contentDescription="Fast forward Adhan",onClick=function() if duaMp then pcall(function() local n=duaMp.getCurrentPosition()+seekSeconds*1000 duaMp.seekTo(math.min(n,duaMp.getDuration())) end) end end},
{Button,text="⏭",layout_weight=1,contentDescription="Next Adhan",onClick=function() if trackIndex<#AZAN_TRACKS then showAzanPlayer(trackIndex+1) end end}
},
{Button,id="btnAzanDownload",text=downloaded and "Delete Offline Copy" or "Download Adhan",layout_width=-1,layout_marginTop="16dp",backgroundColor=downloaded and "#C62828" or "#1976D2",textColor=-1,contentDescription=downloaded and "Delete downloaded Adhan" or "Download Adhan for offline"},
{Button,text="Set as city Adhan",layout_width=-1,layout_marginTop="8dp",backgroundColor="#00695C",textColor=-1,contentDescription="Set this Adhan as the selected city prayer-call audio",onClick=function()
prefs.edit().putInt("azanDefaultTrack",trackIndex).apply()
Toast.makeText(activity,"Selected for city prayer schedule.",1).show()
showAzanSchedule()
end},
{Button,text="Prayer Schedule",layout_width=-1,layout_marginTop="6dp",onClick=function() safeRun("showAzanSchedule", showAzanSchedule) end}
})
M.applyWallpaper(mainLayout,bgColor)
btnAzanDownload.onClick=function()
if File(path).exists() then
confirmDelete(path,function() showAzanPlayer(trackIndex) end)
else
local ok,err=pcall(function()
local req=DownloadManager.Request(Uri.parse(track.url))
req.setTitle(track.name) req.setDescription("Adhan audio for offline use")
req.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
req.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS,"Azan_Audio/"..File(path).getName())
activity.getSystemService(Context.DOWNLOAD_SERVICE).enqueue(req)
end)
if ok then Toast.makeText(activity,"Adhan download started; file is saved to Downloads/Azan_Audio.",1).show()
else showErrorDialog("Adhan Download Error",err) end
end
end
updateTask=Runnable({run=function()
if screen=="azanplayer" and duaMp then pcall(function()
local dur=duaMp.getDuration(); local pos=duaMp.getCurrentPosition()
if dur>0 then azanSeekBar.setMax(dur); azanSeekBar.setProgress(pos) end
local function tm(ms) local t=math.floor(ms/1000); return string.format("%02d:%02d",math.floor(t/60),t%60) end
azanCurrentTime.setText(tm(pos)); azanTotalTime.setText(tm(dur))
if duaMp.isPlaying() then btnAzanPlay.setText("⏸ Pause") end
end) end
if screen=="azanplayer" then handler.postDelayed(updateTask,1000) end
end})
handler.post(updateTask)
azanSeekBar.setOnSeekBarChangeListener(SeekBar.OnSeekBarChangeListener{onProgressChanged=function(b,pos,fromUser) if fromUser and duaMp then pcall(function() duaMp.seekTo(pos) end) end end})
end
local AZAN_PRAYERS={{key="Fajr",label="Fajr",timeKey="pFajr"},{key="Dhuhr",label="Dhuhr",timeKey="pDhuhr"},{key="Asr",label="Asr",timeKey="pAsr"},{key="Maghrib",label="Maghrib",timeKey="pMaghrib"},{key="Isha",label="Isha",timeKey="pIsha"}}
local azanReceiverRegistered={}
M.azanAction = function(key) return "quran_majeed_city_azan_"..key end
M.registerCityAzanReceiver = function(key)
local action=M.azanAction(key)
if azanReceiverRegistered[action] then return end
local ok=pcall(function() activity.registerReceiver(IntentFilter(action)) end)
if ok then azanReceiverRegistered[action]=true end
end
function scheduleCityAzans()
local am=activity.getSystemService(Context.ALARM_SERVICE)
local now=os.time()
local flags=PendingIntent.FLAG_UPDATE_CURRENT
if Build.VERSION.SDK_INT>=23 then pcall(function() flags=flags+PendingIntent.FLAG_IMMUTABLE end) end
for n,item in ipairs(AZAN_PRAYERS) do
local action=M.azanAction(item.key)
M.registerCityAzanReceiver(item.key)
local intent=Intent(action)
intent.putExtra("prayer_name",item.label)
intent.putExtra("city_name",savedCity)
local pi=PendingIntent.getBroadcast(activity,7300+n,intent,flags)
pcall(function() am.cancel(pi) end)
if prefs.getBoolean("cityAzanOn_"..item.key,false) then
local clock=prefs.getString(item.timeKey,"00:00")
local hh,mm=clock:match("(%d+):(%d+)")
if hh and mm then
local cal=Calendar.getInstance(TimeZone.getTimeZone(savedPrayerTimezone))
cal.setTimeInMillis(now*1000)
cal.set(Calendar.HOUR_OF_DAY,tonumber(hh))
cal.set(Calendar.MINUTE,tonumber(mm))
cal.set(Calendar.SECOND,0)
cal.set(Calendar.MILLISECOND,0)
if cal.getTimeInMillis()<=now*1000 then cal.add(Calendar.DAY_OF_MONTH,1) end
local alarm=cal.getTimeInMillis()
local scheduled=false
if Build.VERSION.SDK_INT>=23 then
scheduled=pcall(function() am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,alarm,pi) end)
if not scheduled then pcall(function() am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,alarm,pi) end) end
else
pcall(function() am.set(AlarmManager.RTC_WAKEUP,alarm,pi) end)
end
end
end
end
end
function showAzanSchedule()
screen="azanschedule"
local bgColor,textColor=M.getThemeColors()
local root=LinearLayout(activity); root.setOrientation(LinearLayout.VERTICAL); root.setPadding(18,12,18,12); root.setBackgroundColor(Color.parseColor(bgColor))
local scroll=ScrollView(activity); local body=LinearLayout(activity); body.setOrientation(LinearLayout.VERTICAL); body.setPadding(10,10,10,10)
local head=TextView(activity); head.setText("City prayer Azan schedule"); head.setTextSize(21); head.setTypeface(Typeface.DEFAULT_BOLD); head.setTextColor(Color.parseColor(appColorStr)); body.addView(head)
local city=TextView(activity); city.setText("Location: "..savedCity..", "..savedCountry.." ("..savedPrayerTimezone..")   |   Times from prayer-time settings"); city.setTextSize(13); city.setTextColor(Color.parseColor(textColor)); body.addView(city)
local controls={}; local names={}
for i,t in ipairs(AZAN_TRACKS) do names[i]=t.name end
for _,pr in ipairs(AZAN_PRAYERS) do
local row=LinearLayout(activity); row.setOrientation(LinearLayout.VERTICAL); row.setPadding(8,10,8,10)
local cb=CheckBox(activity); cb.setText(pr.label.."  ("..to12Hour(prefs.getString(pr.timeKey,"00:00"))..")"); cb.setTextColor(Color.parseColor(textColor)); cb.setChecked(prefs.getBoolean("cityAzanOn_"..pr.key,false)); row.addView(cb)
local sp=Spinner(activity); sp.setAdapter(ArrayAdapter(activity,android.R.layout.simple_spinner_dropdown_item,names))
local selected=prefs.getInt("cityAzanTrack_"..pr.key,prefs.getInt("azanDefaultTrack",1)); sp.setSelection(math.max(0,math.min(#names,selected)-1)); row.addView(sp)
local rule=View(activity); rule.setBackgroundColor(0x22000000); local lp=LinearLayout.LayoutParams(-1,1); row.addView(rule,lp)
body.addView(row); controls[pr.key]={check=cb,spinner=sp,timeKey=pr.timeKey}
end
local note=TextView(activity); note.setText("Enable Alarms & reminders for precise alarms. If exact-alarm access is unavailable, Android may deliver an inexact alarm. This in-script schedule requires the host app to keep its registered receiver available; force-stop/reboot persistence depends on the host project manifest and boot receiver."); note.setTextSize(12); note.setTextColor(0xFF9E3A00); note.setPadding(4,12,4,12); body.addView(note)
scroll.addView(body); root.addView(scroll)
local notify=Button(activity); notify.setText("Allow notifications"); notify.setContentDescription("Grant notification permission for scheduled Azan alerts"); root.addView(notify)
local exact=Button(activity); exact.setText("Open exact alarm access settings"); exact.setContentDescription("Open Android Alarms and reminders access"); root.addView(exact)
local save=Button(activity); save.setText("Save and schedule next prayers"); save.setContentDescription("Save city prayer settings and schedule Azan notifications"); root.addView(save)
local play=Button(activity); play.setText("Open Adhan audio player"); root.addView(play)
local back=Button(activity); back.setText("Back"); root.addView(back)
activity.setContentView(root)
notify.setOnClickListener(View.OnClickListener{onClick=function()
pcall(function()
if Build.VERSION.SDK_INT>=33 and activity.checkSelfPermission("android.permission.POST_NOTIFICATIONS")~=0 then
local perms=luajava.newArray("java.lang.String",1); perms[0]="android.permission.POST_NOTIFICATIONS"; activity.requestPermissions(perms,2607)
else Toast.makeText(activity,"Notifications are already allowed (or not runtime-gated on this Android version).",1).show() end
end)
end})
exact.setOnClickListener(View.OnClickListener{onClick=function()
pcall(function()
local i=Intent("android.settings.REQUEST_SCHEDULE_EXACT_ALARM")
i.setData(Uri.parse("package:"..activity.getPackageName()))
activity.startActivity(i)
end)
end})
save.setOnClickListener(View.OnClickListener{onClick=function()
local ed=prefs.edit()
for _,pr in ipairs(AZAN_PRAYERS) do local c=controls[pr.key]; ed.putBoolean("cityAzanOn_"..pr.key,c.check.isChecked()); ed.putInt("cityAzanTrack_"..pr.key,c.spinner.getSelectedItemPosition()+1) end
ed.apply(); scheduleCityAzans()
Toast.makeText(activity,"City-wise Azan schedule saved for "..savedCity..".",1).show()
end})
play.setOnClickListener(View.OnClickListener{onClick=function() safeRun("showAzan", showAzan) end})
back.setOnClickListener(View.OnClickListener{onClick=function() safeRun("showAzan", showAzan) end})
end
showAzan = function()
screen = "azan"
M.stopPlayer()
local bgColor, textColor = M.getThemeColors()
local labels = {}
for i, track in ipairs(AZAN_TRACKS) do
local downloaded = File(M.getAzanLocalPath(i)).exists()
labels[i] = track.name .. (downloaded and "  [Offline]" or "  [Download available]")
end
activity.setContentView(loadlayout{
LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor,
{LinearLayout, orientation=0, padding="10dp", backgroundColor="#00695C", layout_width=-1, gravity="center_vertical",
{Button, text="Back", contentDescription="Back to More", onClick=function() safeRun("showMore", showMore) end},
{TextView, text="Adhan Audio", textSize="18sp", typeface=Typeface.DEFAULT_BOLD, layout_marginLeft="10dp", textColor=-1}
},
{TextView, text="City: "..savedCity..", "..savedCountry..". Tap a recording to open the Quran-style player.", textSize="12sp", textColor=textColor, padding="10dp"},
{Button,text="Set city prayer schedule",layout_width=-1,layout_margin="8dp",backgroundColor="#1976D2",textColor=-1,contentDescription="Set automatic city-wise prayer Azan schedule",onClick=function() safeRun("showAzanSchedule", showAzanSchedule) end},
{ListView, id="azanList", layout_width=-1, layout_height=0, layout_weight=1},
{Button, text="Back to More", layout_width=-1, contentDescription="Back to More", onClick=function() safeRun("showMore", showMore) end}
})
M.applyWallpaper(mainLayout, bgColor)
azanList.setAdapter(ArrayAdapter(activity, android.R.layout.simple_list_item_1, labels))
azanList.onItemClick = function(l, v, p, pos)
local i = pos + 1
local track = AZAN_TRACKS[i]
local path = M.getAzanLocalPath(i)
showAzanPlayer(i)
end
end
M.playDuaAtIndex = function(idx, refreshFn)
local list = duaListOverride or audioDuasCache
if idx < 1 or idx > #list then return end
duaPlayerIndex = idx
local d = list[idx]
M.playReliable(d.audio, M.getDuaAudioLocal(d), d.title, refreshFn, function()
if idx < #list then M.playDuaAtIndex(idx+1, refreshFn) elseif refreshFn then refreshFn() end
end)
end
function showDuaPlayer(idx)
screen = "duaplayer"
local list = duaListOverride or audioDuasCache
if idx < 1 or idx > #list then return end
duaPlayerIndex = idx
local d = list[idx]
local localPath = M.getDuaAudioLocal(d)
local isDownloaded = File(localPath).exists()
local bgColor, textColor = M.getThemeColors()
activity.setContentView(loadlayout{
LinearLayout, id="mainLayout", orientation=1, padding="20dp", layout_width=-1, layout_height=-1, gravity="center", backgroundColor=bgColor,
{TextView, text=(isDownloaded and "Offline Mode" or "Online Stream") .. " - " .. idx .. "/" .. #list, textSize="14sp", layout_marginBottom="10dp", textColor=appColorStr},
{TextView, text=d.title, textSize="24sp", typeface=Typeface.DEFAULT_BOLD, layout_marginBottom="8dp", textColor=appColorStr, gravity="center", contentDescription=d.title},
{TextView, text=(d.ar and d.ar ~= "" and d.ar or ""), textSize="18sp", layout_marginBottom="6dp", textColor=appColorStr, gravity="center"},
{TextView, text=d.ur or "", textSize="15sp", layout_marginBottom="8dp", textColor=textColor, gravity="center"},
{TextView, text=d.en or "", textSize="14sp", layout_marginBottom="8dp", textColor=textColor, gravity="center", contentDescription="English dua meaning or audio description"},
{TextView, text=d.en or "", textSize="14sp", layout_marginBottom="8dp", textColor=textColor, gravity="center", contentDescription="English meaning or audio description"},
{TextView, text=(d.tip and d.tip ~= "" and ("💡 " .. d.tip) or (d.cat and ("Category: " .. d.cat) or "")), textSize="12sp", textColor="#777777", layout_marginBottom="12dp", gravity="center"},
{SeekBar, id="skBar", layout_width=-1, layout_marginBottom="8dp"},
{LinearLayout, orientation=0, gravity="center_vertical", layout_width=-1, layout_marginBottom="10dp",
{TextView, text="Speed:", textSize="13sp", textColor=textColor, layout_marginRight="8dp"},
{Spinner, id="duaSpeedSpinner", layout_width=0, layout_weight=1}
},
{LinearLayout, orientation=0, gravity="center", layout_width=-1,
{Button, text="⏮", textSize="14sp", layout_weight=1, layout_margin="2dp", contentDescription="Previous", onClick=function() if duaPlayerIndex>1 then showDuaPlayer(duaPlayerIndex-1) end end},
{Button, text="⏪ "..seekSeconds.."s", textSize="16sp", layout_weight=1, layout_margin="2dp", contentDescription="Rewind", onClick=function() if duaMp then pcall(function() local n=duaMp.getCurrentPosition()-(seekSeconds*1000) if n<0 then n=0 end duaMp.seekTo(n) end) end end},
{Button, id="btnDuaPlayPause", text="⏸ " .. tr("Pause"), textSize="16sp", typeface=Typeface.DEFAULT_BOLD, layout_weight=1.5, layout_margin="2dp", contentDescription="Play or Pause", onClick=function()
safeRun("toggleDuaPlayPause", function()
local now = os.time()
if now - (PS.duaLastToggle or 0) < 1 then return end
PS.duaLastToggle = now
local playing = false
pcall(function() if duaMp then playing = duaMp.isPlaying() end end)
if playing then
PS.duaWanted = false PS.duaState = "paused"
PS.duaGen = (PS.duaGen or 0) + 1
pcall(function() duaMp.pause() end)
pcall(function() duaMp.setWakeMode(activity, 0) end)
if V25.clipTask then pcall(function() handler.removeCallbacks(V25.clipTask) end) end
if btnDuaPlayPause then btnDuaPlayPause.setText("▶ " .. tr("Play")) end
elseif PS.duaWanted == true and duaMp ~= nil then
PS.duaWanted = false PS.duaState = "idle"
PS.duaGen = (PS.duaGen or 0) + 1
pcall(function() duaMp.reset() duaMp.release() end) duaMp = nil
if btnDuaPlayPause then btnDuaPlayPause.setText("▶ " .. tr("Play")) end
Toast.makeText(activity, "Streaming cancel ho gayi.", 0).show()
elseif PS.duaState == "paused" and duaMp ~= nil then
PS.duaWanted = true PS.duaState = "playing"
pcall(function() duaMp.setWakeMode(activity, PowerManager.PARTIAL_WAKE_LOCK) end)
pcall(function() duaMp.start() end)
if btnDuaPlayPause then btnDuaPlayPause.setText("⏸ " .. tr("Pause")) end
else
PS.duaWanted = true PS.duaState = "loading"
if btnDuaPlayPause then btnDuaPlayPause.setText("⏸ " .. tr("Pause")) end
M.playReliable(d.audio, localPath, d.title, nil, function()
if btnDuaPlayPause then btnDuaPlayPause.setText("▶ " .. tr("Play")) end
if duaPlayerIndex < #list then showDuaPlayer(duaPlayerIndex+1) end
end, d.startAt, d.endAt)
end
end)
end},
{Button, text=seekSeconds.."s ⏩", textSize="16sp", layout_weight=1, layout_margin="2dp", contentDescription="Fast Forward", onClick=function() if duaMp then pcall(function() local n=duaMp.getCurrentPosition()+(seekSeconds*1000) duaMp.seekTo(n) end) end end},
{Button, text="⏭", textSize="14sp", layout_weight=1, layout_margin="2dp", contentDescription="Next", onClick=function() if duaPlayerIndex<#list then showDuaPlayer(duaPlayerIndex+1) end end}
},
{Button, id="btnDuaDownload", text=isDownloaded and "🗑 Delete Offline" or "⬇️ Download", textSize="14sp", layout_width=-1, layout_marginTop="20dp", backgroundColor=isDownloaded and "#C62828" or "#1976D2", textColor=-1, contentDescription=isDownloaded and "Delete Offline Copy" or "Download"},
{LinearLayout, orientation=0, gravity="center", layout_marginTop="30dp", layout_width=-1,
{Button, text=tr("Back"), layout_weight=1, layout_marginRight="10dp", contentDescription="Back", onClick=function() safeRun("duaBack", (V25.duaBackFn or showDailyDuas)) end},
{Button, text="Exit App", layout_weight=1, backgroundColor="#C62828", textColor=-1, onClick=function() safeRun("exitApp", function() M.stopPlayer(function() pcall(function() if duaMp then duaMp.stop() duaMp.release() end end) duaMp = nil activity.finish() end) end) end}
}
})
M.applyWallpaper(mainLayout, bgColor)
do
local speedLabels = {"0.75x", "1.0x (Normal)", "1.25x", "1.5x", "2.0x"}
local speedValues = {0.75, 1.0, 1.25, 1.5, 2.0}
local speedIndex = 1
for i,v in ipairs(speedValues) do if math.abs(v - PS.speed) < 0.01 then speedIndex = i - 1 break end end
duaSpeedSpinner.setAdapter(ArrayAdapter(activity, android.R.layout.simple_spinner_dropdown_item, speedLabels))
duaSpeedSpinner.setSelection(speedIndex)
duaSpeedSpinner.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{onItemSelected=function(p,v,pos,id)
savePlaybackSpeed(speedValues[pos+1])
if duaMp then applyPlaybackSpeed(duaMp) end
end})
end
btnDuaDownload.onClick = function()
if File(localPath).exists() then
confirmDelete(localPath, function() showDuaPlayer(duaPlayerIndex) end)
else
local ok, err = pcall(function()
local req = DownloadManager.Request(Uri.parse(d.audio))
req.setTitle(d.title)
req.setDescription("Downloading dua audio...")
req.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
req.setDestinationUri(Uri.fromFile(File(localPath)))
activity.getSystemService(Context.DOWNLOAD_SERVICE).enqueue(req)
end)
if not ok then
showErrorDialog("Dua Download Error", err)
return
end
Toast.makeText(activity, "Download shuru - kuch dair baad Play dabayein (offline chalega).", 1).show()
end
end
M.playReliable(d.audio, localPath, d.title, nil, function()
if btnDuaPlayPause then btnDuaPlayPause.setText("▶ " .. tr("Play")) end
if duaPlayerIndex < #list then showDuaPlayer(duaPlayerIndex+1) end
end, d.startAt, d.endAt)
updateTask = Runnable({run = function()
if duaMp then pcall(function() if duaMp.isPlaying() then skBar.setMax(duaMp.getDuration()) skBar.setProgress(duaMp.getCurrentPosition()) end end) end
handler.postDelayed(updateTask, 1000)
end})
handler.post(updateTask)
skBar.setOnSeekBarChangeListener(SeekBar.OnSeekBarChangeListener{onProgressChanged=function(s, p, f) if f and duaMp then pcall(function() duaMp.seekTo(p) end) end end})
end
function showDailyDuas()
screen = "dailyduas"
M.stopPlayer()
duaListOverride = nil
V25.duaBackFn = nil
local bgColor, textColor = M.getThemeColors()
local list = M.buildAudioDuasList()
local textDuas = {}
for _, d in ipairs(dailyDuas()) do if d.audio == "" then table.insert(textDuas, d) end end
local audioRows = {}
table.insert(audioRows, {TextView, text="🔊 Audio Duas (" .. #list .. ") - tap any dua to open", textSize="15sp", typeface=Typeface.DEFAULT_BOLD, textColor=-1, backgroundColor="#00897B", padding="8dp", contentDescription="Audio Duas category, " .. #list .. " duas. Tap a dua to open the full player"})
local audioCats = {} local audioCatItems = {}
for i, d in ipairs(list) do
if not audioCatItems[d.cat] then table.insert(audioCats, d.cat) audioCatItems[d.cat] = {} end
table.insert(audioCatItems[d.cat], i)
end
for _, cat in ipairs(audioCats) do
table.insert(audioRows, {TextView, text=cat .. " (" .. #audioCatItems[cat] .. ")", textSize="13sp", typeface=Typeface.DEFAULT_BOLD, textColor=appColorStr, padding="6dp", contentDescription=cat .. " category, " .. #audioCatItems[cat] .. " audio duas"})
for _, i in ipairs(audioCatItems[cat]) do
local d = list[i]
table.insert(audioRows, {
Button, text=d.title, textSize="13sp", layout_width=-1, gravity="left|center_vertical", padding="12dp", layout_marginBottom="2dp", backgroundColor="#12000000", textColor=textColor, contentDescription="Audio dua: " .. d.title .. ". Tap to open player", onClick=function() showDuaPlayer(i) end
})
end
end
local textRows = {}
table.insert(textRows, {TextView, text="📝 Text Only Duas (" .. #textDuas .. ")", textSize="15sp", typeface=Typeface.DEFAULT_BOLD, textColor=-1, backgroundColor="#607D8B", padding="8dp", layout_marginTop="10dp", contentDescription="Text only duas category, " .. #textDuas .. " duas, no audio available"})
local cats = {} local catItems = {}
for _, d in ipairs(textDuas) do
if not catItems[d.cat] then table.insert(cats, d.cat) catItems[d.cat] = {} end
table.insert(catItems[d.cat], d)
end
for _, cat in ipairs(cats) do
table.insert(textRows, {TextView, text=cat, textSize="13sp", typeface=Typeface.DEFAULT_BOLD, textColor=appColorStr, padding="6dp", contentDescription=cat .. " category"})
for _, d in ipairs(catItems[cat]) do
table.insert(textRows, {
LinearLayout, orientation=1, layout_width=-1, padding="12dp", layout_marginBottom="2dp", backgroundColor="#12000000",
{TextView, text=d.title, textSize="14sp", typeface=Typeface.DEFAULT_BOLD, textColor=appColorStr, contentDescription="Text dua: " .. d.title .. ", no audio available"},
{TextView, text=d.ar, textSize="18sp", typeface=Typeface.DEFAULT_BOLD, textColor=textColor, gravity="right", layout_marginTop="4dp"},
{TextView, text=d.ur, textSize="14sp", textColor=textColor, gravity="right", layout_marginTop="2dp"},
{TextView, text=d.en or "", textSize="14sp", textColor=textColor, gravity="left", layout_marginTop="5dp", contentDescription="English translation or description"},
{TextView, text="💡 " .. d.tip, textSize="11sp", textColor="#777777", layout_marginTop="4dp"},
(d.link and d.link ~= "" and {Button, text="▶️ Online sunnein (source page)", textSize="12sp", layout_width=-1, layout_marginTop="6dp", backgroundColor="#00897B", textColor=-1, contentDescription="Online audio source page for " .. d.title, onClick=function() safeRun("Dua source page", M.openLinkAndClose, d.link) end} or {TextView, text="", textSize="1sp"})
})
end
end
local content = {LinearLayout, orientation=1, layout_width=-1, layout_height=-2}
for _, r in ipairs(audioRows) do table.insert(content, r) end
for _, r in ipairs(textRows) do table.insert(content, r) end
activity.setContentView(loadlayout{
LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor,
{LinearLayout, orientation=0, padding="10dp", backgroundColor="#00695C", layout_width=-1, gravity="center_vertical",
{Button, text=tr("Back"), onClick=function() safeRun("showHome", showHome) end},
{TextView, text=tr("Daily Masnoon Duas"), textSize="16sp", typeface=Typeface.DEFAULT_BOLD, layout_marginLeft="10dp", textColor=-1}
},
{LinearLayout, orientation=0, layout_width=-1, padding="8dp",
{Button, text="▶️ Full Audio (Vol 1: Hisnul Muslim CD1)", textSize="11sp", layout_weight=1, layout_marginRight="4dp", backgroundColor="#00897B", textColor=-1, contentDescription="Play full Hisnul Muslim recording, volume 1", onClick=function()
M.playReliable("https://archive.org/download/HisnulMuslimAudio/CD%201.mp3", duaAudioDir .. "hisnul_muslim_vol1.mp3", "Hisnul Muslim Vol 1", nil, nil)
end},
{Button, text="▶️ Full Audio (Vol 2: Hisnul Muslim CD2)", textSize="11sp", layout_weight=1, backgroundColor="#00897B", textColor=-1, contentDescription="Play full Hisnul Muslim recording, volume 2", onClick=function()
M.playReliable("https://archive.org/download/HisnulMuslimAudio/CD%202.mp3", duaAudioDir .. "hisnul_muslim_vol2.mp3", "Hisnul Muslim Vol 2", nil, nil)
end}
},
{TextView, text="⚠️ Vol 1/Vol 2 mein KAUN SI dua kis waqt aati hai iski official track-list kahin published nahi hai (yeh sirf 2 lambi recordings hain, alag-alag tracks nahi) - is liye neeche 'Audio Duas' list mein har dua alag se individually verified hai, wahi use karein agar specific dua sunni ho.", textSize="10sp", textColor="#C62828", padding="8dp"},
{ScrollView, layout_width=-1, layout_height=0, layout_weight=1, content},
M.bottomTabs("duas")
})
M.applyWallpaper(mainLayout, bgColor)
end
function V25.kalimaHasAudio(d) return (d ~= nil and d.audio ~= nil and tostring(d.audio) ~= "") end
function V25.kalimaItems()
local out = {}
local ok, err = pcall(function()
for _, d in ipairs(dailyDuas()) do
if tostring(d.cat or "") == "6 Kalme / Iman / Namaz" then table.insert(out, d) end
end
end)
if not ok then showErrorDialog("6 Kalme list", err) end
return out
end
function V25.kalimaPartTitle(d)
if not d then return "" end
local t = tostring(d.title)
if d.startAt and d.startAt > 0 then
return t .. "   [clip " .. math.floor(d.startAt/60) .. "m se]"
end
return t
end
function V25.openKalimaItem(d)
if not d then return end
if V25.kalimaHasAudio(d) then
M.buildAudioDuasList()
for ai, ad in ipairs(audioDuasCache) do
if ad == d then showDuaPlayer(ai) return end
end
M.playReliable(d.audio, M.getDuaAudioLocal(d), tostring(d.title), nil, nil, d.startAt, d.endAt)
return
end
local body = ""
if d.ar and d.ar ~= "" then body = body .. d.ar .. "\n\n" end
if d.ur and d.ur ~= "" then body = body .. d.ur .. "\n\n" end
if d.en and d.en ~= "" then body = body .. d.en end
if d.tip and d.tip ~= "" then body = body .. "\n\n" .. d.tip end
local bld = AlertDialog.Builder(activity).setTitle(tostring(d.title)).setMessage(body)
if d.link and d.link ~= "" then
bld.setNeutralButton("Online sunnein", {onClick=function() safeRun("Open source page", M.openLinkAndClose, d.link) end})
end
bld.setPositiveButton("Copy", {onClick=function() V25.copyTextToClipboard(body) end})
bld.setNegativeButton("Cancel", nil)
bld.show()
end
function showKalimaImanScreen()
screen = "kalima"
safeRun("Stop previous player", M.stopPlayer)
local bgColor, textColor = M.getThemeColors()
local items = V25.kalimaItems()
local labels = {}
for _, d in ipairs(items) do
if V25.kalimaHasAudio(d) then
local tag = "   (online stream"
if d.startAt and d.startAt > 0 then tag = tag .. " - alag clip" end
table.insert(labels, "🔊 " .. tostring(d.title) .. tag .. ")")
else
table.insert(labels, "📝 " .. tostring(d.title) .. "   (text + online link)")
end
end
if #labels == 0 then table.insert(labels, "Koi item nahi mila - app dobara kholein") end
activity.setContentView(loadlayout{
LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor,
{LinearLayout, orientation=0, padding="10dp", backgroundColor="#00695C", layout_width=-1, gravity="center_vertical",
{Button, text=tr("Back"), contentDescription="Back to More menu", onClick=function() safeRun("Back to More", showMore) end},
{TextView, text="6 Kalme / Iman / Namaz", textSize="16sp", typeface=Typeface.DEFAULT_BOLD, layout_marginLeft="10dp", textColor=-1}
},
{TextView, text="🔊 wale items Quran jaisa player kholte hain (online + download + offline). 📝 wale items ka verified direct MP3 nahi mila, is liye unka mukammal text + online source link diya gaya hai.", textSize="11sp", textColor="#777777", padding="8dp"},
{TextView, text="Neeche list mein se koi bhi item tap karein:", textSize="12sp", typeface=Typeface.DEFAULT_BOLD, textColor=appColorStr, padding="8dp"},
{ListView, id="kalimaList", layout_width=-1, layout_height=-1}
})
M.applyWallpaper(mainLayout, bgColor)
kalimaList.setAdapter(ArrayAdapter(activity, android.R.layout.simple_list_item_1, labels))
kalimaList.onItemClick = function(l, v, p, i)
local d = items[i+1]
safeRun("6 Kalme item: " .. tostring(labels[i+1]), V25.openKalimaItem, d)
end
end
function showPara()
screen = "para"
M.stopPlayer()
local bgColor, textColor = M.getThemeColors()
local items = {}
for i, n in ipairs(paraNames) do table.insert(items, n) end
activity.setContentView(loadlayout{
LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor,
{LinearLayout, orientation=0, padding="10dp", backgroundColor="#2E7D32", layout_width=-1, gravity="center_vertical",
{Button, text=tr("Back"), backgroundColor="#1B5E20", textColor=-1, onClick=function() safeRun("showMore", showMore) end},
{TextView, text="30 Para (Juz-wise)", textSize="16sp", typeface=Typeface.DEFAULT_BOLD, layout_marginLeft="10dp", textColor=-1}
},
{TextView, text="Har Para tap karein - us Juz ki Surahon ki list khulegi (play/download).", textSize="11sp", padding="8dp", textColor=textColor},
{ListView, id="paraList", layout_width=-1, layout_height=-1}
})
M.applyWallpaper(mainLayout, bgColor)
paraList.setAdapter(ArrayAdapter(activity, android.R.layout.simple_list_item_1, items))
paraList.onItemClick = function(l, v, p, i) showParaSurahs(i+1) end
end
function showParaSurahs(paraNum)
screen = "parasurahs"
local bgColor, textColor = M.getThemeColors()
local startS = paraSurahStart[paraNum]
local endS = (paraNum < 30) and paraSurahStart[paraNum+1] or 114
local list = {}
for s = startS, endS do table.insert(list, s) end
if #list == 0 then list = {startS} end
local nextParaFirstSurah = (paraNum < 30) and paraSurahStart[paraNum+1] or 115
local nextParaFirstAyah = (paraNum < 30) and (paraFirstAyah[paraNum+1] or 1) or 1
local startAyahs = {}
local endAyahs = {}
local names = {}
for idx, s in ipairs(list) do
local sAyah = (idx == 1) and (paraFirstAyah[paraNum] or 1) or 1
local eAyah
if idx == #list and s == nextParaFirstSurah then
eAyah = nextParaFirstAyah - 1
else
eAyah = surahAyahCounts[s] or 1
end
startAyahs[idx] = sAyah
endAyahs[idx] = eAyah
if sAyah == 1 and eAyah == (surahAyahCounts[s] or 1) then
table.insert(names, surahNames[s])
else
table.insert(names, surahNames[s] .. " (Ayat " .. sAyah .. "-" .. eAyah .. ")")
end
end
activity.setContentView(loadlayout{
LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor,
{LinearLayout, orientation=0, padding="10dp", backgroundColor="#2E7D32", layout_width=-1, gravity="center_vertical",
{Button, text=tr("Back"), backgroundColor="#1B5E20", textColor=-1, onClick=function() safeRun("showPara", showPara) end},
{TextView, text="Para " .. paraNum, textSize="16sp", typeface=Typeface.DEFAULT_BOLD, layout_marginLeft="10dp", textColor=-1}
},
{ListView, id="psList", layout_width=-1, layout_height=-1}
})
M.applyWallpaper(mainLayout, bgColor)
psList.setAdapter(ArrayAdapter(activity, android.R.layout.simple_list_item_1, names))
psList.onItemClick = function(l, v, p, i)
local idx = i + 1
if startAyahs[idx] > 1 then
showAyahByAyah(list[idx], startAyahs[idx])
else
showPlayer(list[idx])
end
end
end
function showNamesOfAllah()
screen = "names"
local bgColor, textColor = M.getThemeColors()
local listLayout = {LinearLayout, orientation=1, layout_width=-1, layout_height=-2, padding="15dp"}
for i, name in ipairs(asmaUlHusna) do
table.insert(listLayout, {
LinearLayout, orientation=1, layout_width=-1, layout_marginBottom="15dp", padding="15dp", backgroundColor="#1A000000",
{TextView, text=tostring(i) .. ". " .. name.ar, textSize="28sp", typeface=Typeface.DEFAULT_BOLD, textColor=appColorStr, gravity="right"},
{TextView, text=name.ro, textSize="18sp", textColor=textColor, gravity="center_horizontal", layout_marginTop="5dp"},
{TextView, text=name.ur, textSize="16sp", textColor=textColor, gravity="right", layout_marginTop="5dp"}
})
end
local namesAudioUrls = { "https://archive.org/download/99-names-of-allah-asma-ul-husna/99%20names%20of%20Allah%20%20Asma%20Ul%20husna.mp3", "https://archive.org/download/AsmaulHusnaMP3/Asmaul%20Husna%20dan%20Artinya%20Asmaul%20Husna%20Mp3%20Asmaul%20Husna%20Beserta%20Artinya%2099%20Asmaul%20Husna%20Asma%20Ul%20Husna%2099%20Nama%20Allah%20TVRI%20Nasional%20Asma%20Ul%20Husna%20TV3%20Dzikir%20Ary%20Ginanjar%20Agustian%20Names%20of%20Allah%20sifat-sifat%20Allah%20pengertian%20asmaul%20husna.mp3", "https://archive.org/download/asma-ul-husna-99-names-of-allah/Asma_ul_Husna.mp3" }
local namesLocalPath = duaAudioDir .. "asma_ul_husna_full.mp3"
local namesDownloaded = File(namesLocalPath).exists()
activity.setContentView(loadlayout{
LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor,
{LinearLayout, orientation=0, padding="10dp", backgroundColor=appColorStr, layout_width=-1, gravity="center_vertical",
{Button, text=tr("Back"), onClick=function() safeRun("showMore", showMore) end},
{TextView, text=tr("99 Names of Allah"), textSize="18sp", typeface=Typeface.DEFAULT_BOLD, layout_marginLeft="10dp", textColor=-1}
},
{LinearLayout, orientation=0, layout_width=-1, layout_margin="10dp",
{Button, id="btnNamesPlayPause", text="▶️ Play Full Audio", textSize="13sp", layout_weight=1, layout_marginRight="4dp", backgroundColor="#8E24AA", textColor=-1},
{Button, id="btnNamesDownload", text=namesDownloaded and "🗑 Delete Offline" or "⬇️ Download", textSize="13sp", layout_weight=1, backgroundColor=namesDownloaded and "#C62828" or "#1976D2", textColor=-1}
},
{ScrollView, layout_width=-1, layout_height=-1,
listLayout
}
})
M.applyWallpaper(mainLayout, bgColor)
btnNamesPlayPause.onClick = function()
if duaMp then
pcall(function()
if duaMp.isPlaying() then
duaMp.pause()
btnNamesPlayPause.setText("▶️ Play Full Audio")
else
duaMp.start()
btnNamesPlayPause.setText("⏸ Pause")
end
end)
else
pcall(function() btnNamesPlayPause.setText("⏸ Pause") end)
M.playReliable(namesAudioUrls, namesLocalPath, "99 Names of Allah - Full Audio", nil, function()
pcall(function() btnNamesPlayPause.setText("▶️ Play Full Audio") end)
end)
end
end
btnNamesDownload.onClick = function()
if File(namesLocalPath).exists() then
confirmDelete(namesLocalPath, function() showNamesOfAllah() end)
else
local ok, err = pcall(function()
local req = DownloadManager.Request(Uri.parse(namesAudioUrls[1]))
req.setTitle("99 Names of Allah - Full Audio")
req.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
req.setDestinationUri(Uri.fromFile(File(namesLocalPath)))
activity.getSystemService(Context.DOWNLOAD_SERVICE).enqueue(req)
end)
if ok then
Toast.makeText(activity, "Download shuru ho gaya... khatam hote hi is screen par wapis aakar offline sunein.", 1).show()
else
showErrorDialog("99 Names Download Error", err)
end
end
end
end
function showAsmaNabi()
screen = "asmanabi"
local bgColor, textColor = M.getThemeColors()
local listLayout2 = {LinearLayout, orientation=1, layout_width=-1, layout_height=-2, padding="15dp"}
for i, name in ipairs(asmaNabi) do
table.insert(listLayout2, {
LinearLayout, orientation=1, layout_width=-1, layout_marginBottom="15dp", padding="15dp", backgroundColor="#1A000000",
{TextView, text=tostring(i) .. ". " .. name.ar, textSize="28sp", typeface=Typeface.DEFAULT_BOLD, textColor=appColorStr, gravity="right", contentDescription="Name number " .. i},
{TextView, text=name.ro, textSize="18sp", textColor=textColor, gravity="center_horizontal", layout_marginTop="5dp"},
{TextView, text=name.ur, textSize="16sp", textColor=textColor, gravity="right", layout_marginTop="5dp"}
})
end
activity.setContentView(loadlayout{
LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor,
{LinearLayout, orientation=0, padding="10dp", backgroundColor=appColorStr, layout_width=-1, gravity="center_vertical",
{Button, text=tr("Back"), contentDescription="Back to More", onClick=function() safeRun("showMore", showMore) end},
{TextView, text="Blessed Names of Prophet Muhammad", textSize="16sp", typeface=Typeface.DEFAULT_BOLD, layout_marginLeft="10dp", textColor=-1}
},
{ScrollView, layout_width=-1, layout_height=-1,
listLayout2
}
})
M.applyWallpaper(mainLayout, bgColor)
end
function showProgressTracker()
screen = "progresstracker"
local bgColor, textColor = M.getThemeColors()
local rows = {}
local completedCount = 0
for i, name in ipairs(surahNames) do
local status = "Not started"
local statusColor = "#999999"
if completedSurahs[i] then
status = "Completed (full Surah listened)"
statusColor = "#2E7D32"
completedCount = completedCount + 1
elseif lastAyahProgress[i] then
status = "In progress - Ayat " .. lastAyahProgress[i] .. " / " .. (surahAyahCounts[i] or "?")
statusColor = "#FF8F00"
elseif lastRukuProgress[i] then
status = "In progress - Ruku " .. lastRukuProgress[i]
statusColor = "#FF8F00"
end
if status ~= "Not started" then
table.insert(rows, {
LinearLayout, orientation=1, layout_width=-1, padding="10dp", layout_marginBottom="2dp", backgroundColor="#12000000",
{TextView, text=i .. ". " .. name, textSize="14sp", typeface=Typeface.DEFAULT_BOLD, textColor=appColorStr},
{TextView, text=status, textSize="12sp", textColor=statusColor}
})
end
end
local content = {LinearLayout, orientation=1, layout_width=-1, layout_height=-2}
if #rows == 0 then
table.insert(content, {TextView, text="Koi Surah abhi shuru nahi ki. Kisi Surah, Ayat-ba-Ayat, ya Ruku mode ko use karein, progress yahan dikhegi.", textSize="13sp", textColor=textColor, padding="15dp"})
else
for _, r in ipairs(rows) do table.insert(content, r) end
end
activity.setContentView(loadlayout{
LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor,
{LinearLayout, orientation=0, padding="10dp", backgroundColor=appColorStr, layout_width=-1, gravity="center_vertical",
{Button, text=tr("Back"), onClick=function() safeRun("showMore", showMore) end},
{TextView, text="Progress Tracker", textSize="16sp", typeface=Typeface.DEFAULT_BOLD, layout_marginLeft="10dp", textColor=-1}
},
{TextView, text=completedCount .. " / 114 Surah completed", textSize="13sp", typeface=Typeface.DEFAULT_BOLD, textColor=textColor, padding="10dp"},
{ScrollView, layout_width=-1, layout_height=-1, content}
})
M.applyWallpaper(mainLayout, bgColor)
end
function showStorageManager()
screen = "storagemanager"
local bgColor, textColor = M.getThemeColors()
local function dirSizeAndCount(dir)
local total = 0
local count = 0
pcall(function()
local f = File(dir)
if f.exists() and f.isDirectory() then
local files = f.listFiles()
if files then
for i=0, files.length-1 do
total = total + files[i].length()
count = count + 1
end
end
end
end)
return total, count
end
local surahBytes, surahCount = dirSizeAndCount(downloadDir)
local ayahBytes, ayahCount = dirSizeAndCount(ayahAudioDir)
local duaBytes, duaCount = dirSizeAndCount(duaAudioDir)
local totalMB = string.format("%.1f", (surahBytes + ayahBytes + duaBytes) / (1024*1024))
activity.setContentView(loadlayout{
LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor,
{LinearLayout, orientation=0, padding="10dp", backgroundColor=appColorStr, layout_width=-1, gravity="center_vertical",
{Button, text=tr("Back"), onClick=function() safeRun("showMore", showMore) end},
{TextView, text="Storage Manager", textSize="16sp", typeface=Typeface.DEFAULT_BOLD, layout_marginLeft="10dp", textColor=-1}
},
{LinearLayout, orientation=1, padding="15dp",
{TextView, text="Total downloaded: " .. totalMB .. " MB", textSize="18sp", typeface=Typeface.DEFAULT_BOLD, textColor=appColorStr, layout_marginBottom="15dp"},
{TextView, text="Surahs (whole-Surah downloads): " .. string.format("%.1f", surahBytes/(1024*1024)) .. " MB (" .. surahCount .. " files)", textSize="14sp", textColor=textColor, layout_marginBottom="8dp"},
{TextView, text="Ayat-ba-Ayat / Ruku audio: " .. string.format("%.1f", ayahBytes/(1024*1024)) .. " MB (" .. ayahCount .. " files)", textSize="14sp", textColor=textColor, layout_marginBottom="8dp"},
{TextView, text="Duas audio: " .. string.format("%.1f", duaBytes/(1024*1024)) .. " MB (" .. duaCount .. " files)", textSize="14sp", textColor=textColor, layout_marginBottom="20dp"},
{Button, text="Clear All Downloads", textSize="14sp", backgroundColor="#C62828", textColor=-1, onClick=function()
AlertDialog.Builder(activity).setTitle("Clear All Downloads").setMessage("Yeh Surahs, Ayat-ba-Ayat/Ruku audio, aur Duas audio - sab downloaded files delete kar dega. Yaqeen hai?").setPositiveButton("Yes, Delete All", {onClick=function()
local function clearDir(dir)
pcall(function()
local f = File(dir)
if f.exists() and f.isDirectory() then
local files = f.listFiles()
if files then for i=0, files.length-1 do pcall(function() files[i].delete() end) end end
end
end)
end
clearDir(downloadDir) clearDir(ayahAudioDir) clearDir(duaAudioDir)
Toast.makeText(activity, "Saari downloads delete ho gayin.", 1).show()
showStorageManager()
end}).setNegativeButton("Cancel", nil).show()
end}
}
})
M.applyWallpaper(mainLayout, bgColor)
end
function showFullQuranScreen()
screen = "fullquranlist"
M.stopPlayer()
local bgColor, textColor = M.getThemeColors()
local names = {}
for i, v in ipairs(fullQuranVoices) do table.insert(names, v.name) end
activity.setContentView(loadlayout{
LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor,
{LinearLayout, orientation=0, padding="10dp", backgroundColor="#3E2723", layout_width=-1, gravity="center_vertical",
{Button, text=tr("Back"), onClick=function() safeRun("showMore", showMore) end},
{TextView, text="Poori Quran (Continuous)", textSize="16sp", typeface=Typeface.DEFAULT_BOLD, layout_marginLeft="10dp", textColor=-1}
},
{TextView, text="Yeh EK hi bari (kai ghante lambi) file hai - Surah-wise seek nahi hoti, sirf continuous sunein ya scrub karein. Reciter select karein:", textSize="12sp", textColor="#C62828", padding="10dp"},
{ListView, id="fqList", layout_width=-1, layout_height=0, layout_weight=1}
})
M.applyWallpaper(mainLayout, bgColor)
fqList.setAdapter(ArrayAdapter(activity, android.R.layout.simple_list_item_1, names))
fqList.onItemClick = function(l, v, p, i) showFullQuranPlayer(i + 1) end
end
function showFullQuranPlayer(voiceIdx)
screen = "fullquranplayer"
local voice = fullQuranVoices[voiceIdx]
local localPath = M.getFullQuranLocal(voice)
local isDownloaded = File(localPath).exists()
local bgColor, textColor = M.getThemeColors()
activity.setContentView(loadlayout{
LinearLayout, id="mainLayout", orientation=1, padding="20dp", layout_width=-1, layout_height=-1, gravity="center", backgroundColor=bgColor,
{TextView, text=(isDownloaded and "Offline Mode" or "Online Stream"), textSize="14sp", layout_marginBottom="10dp", textColor=appColorStr},
{TextView, text=voice.name, textSize="18sp", typeface=Typeface.DEFAULT_BOLD, layout_marginBottom="10dp", textColor=appColorStr, gravity="center"},
{TextView, text="Bari file hai, load hone mein waqt lag sakta hai.", textSize="11sp", textColor="#777777", layout_marginBottom="20dp"},
{SeekBar, id="fqSeekBar", layout_width=-1, layout_marginBottom="10dp"},
{LinearLayout, orientation=0, layout_width=-1, gravity="center", layout_marginBottom="20dp",
{TextView, id="fqCurrentTxt", text="00:00", layout_weight=1, gravity="center"},
{TextView, id="fqTotalTxt", text="00:00", layout_weight=1, gravity="center"}
},
{Button, id="fqPlayPause", text="▶ " .. tr("Play"), textSize="18sp", typeface=Typeface.DEFAULT_BOLD, layout_width=-1, backgroundColor="#3E2723", textColor=-1},
{LinearLayout, orientation=0, layout_width=-1, gravity="center", layout_marginTop="10dp",
{Button, id="fqRwdBtn", text="⏪ "..seekSeconds.."s", textSize="14sp", layout_weight=1, layout_margin="2dp"},
{Button, id="fqFwdBtn", text=seekSeconds.."s ⏩", textSize="14sp", layout_weight=1, layout_margin="2dp"}
},
{Button, id="fqDownload", text=isDownloaded and "🗑 Delete Offline" or "⬇️ Download (bari file)", textSize="14sp", layout_width=-1, layout_marginTop="15dp", backgroundColor=isDownloaded and "#C62828" or "#1976D2", textColor=-1},
{Button, text=tr("Back"), layout_width=-1, layout_marginTop="20dp", onClick=function() safeRun("showFullQuranScreen", showFullQuranScreen) end}
})
M.applyWallpaper(mainLayout, bgColor)
fqPlayPause.onClick = function()
if duaMp then
pcall(function()
if duaMp.isPlaying() then
duaMp.pause()
fqPlayPause.setText("▶ " .. tr("Play"))
else
duaMp.start()
fqPlayPause.setText("⏸ " .. tr("Pause"))
end
end)
else
fqPlayPause.setText("Loading...")
M.playReliable(voice.url, localPath, voice.name, nil, nil)
end
end
fqRwdBtn.onClick = function()
if duaMp then pcall(function()
local np = duaMp.getCurrentPosition() - (seekSeconds*1000)
duaMp.seekTo(np > 0 and np or 0)
end) end
end
fqFwdBtn.onClick = function()
if duaMp then pcall(function()
local np = duaMp.getCurrentPosition() + (seekSeconds*1000)
if np < duaMp.getDuration() then duaMp.seekTo(np) end
end) end
end
fqDownload.onClick = function()
if File(localPath).exists() then
confirmDelete(localPath, function() showFullQuranPlayer(voiceIdx) end)
else
local ok, err = pcall(function()
local req = DownloadManager.Request(Uri.parse(voice.url))
req.setTitle(voice.name)
req.setDescription("Poori Quran download ho rahi hai - bari file, waqt lagega...")
req.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
req.setDestinationUri(Uri.fromFile(File(localPath)))
activity.getSystemService(Context.DOWNLOAD_SERVICE).enqueue(req)
end)
if ok then
Toast.makeText(activity, "Download shuru ho gaya - bari file hai, kaafi waqt lag sakta hai. Notification se progress dekhein.", 1).show()
else
showErrorDialog("Full Quran Download Error", err)
end
end
end
updateTask = Runnable({run = function()
if duaMp then pcall(function()
if duaMp.isPlaying() then
fqSeekBar.setMax(duaMp.getDuration())
fqSeekBar.setProgress(duaMp.getCurrentPosition())
fqCurrentTxt.setText(ft(duaMp.getCurrentPosition()))
fqTotalTxt.setText(ft(duaMp.getDuration()))
end
end) end
handler.postDelayed(updateTask, 1000)
end})
handler.post(updateTask)
fqSeekBar.setOnSeekBarChangeListener(SeekBar.OnSeekBarChangeListener{onProgressChanged=function(s, p, f) if f and duaMp then pcall(function() duaMp.seekTo(p) end) end end})
end
function showHadithScreen()
screen = "hadithlist"
M.stopPlayer()
local bgColor, textColor = M.getThemeColors()
local names = {}
for _, b in ipairs(hadithBooks()) do table.insert(names, "Book " .. b.n .. ": " .. b.title) end
activity.setContentView(loadlayout{
LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor,
{LinearLayout, orientation=0, padding="10dp", backgroundColor="#4E342E", layout_width=-1, gravity="center_vertical",
{Button, text=tr("Back"), onClick=function() safeRun("showMore", showMore) end},
{TextView, text="Sahih Bukhari (English)", textSize="16sp", typeface=Typeface.DEFAULT_BOLD, layout_marginLeft="10dp", textColor=-1}
},
{TextView, text="97 Kitab (Books) - koi bhi select karein", textSize="12sp", textColor="#777777", padding="8dp"},
{ListView, id="hadithList", layout_width=-1, layout_height=0, layout_weight=1}
})
M.applyWallpaper(mainLayout, bgColor)
hadithList.setAdapter(ArrayAdapter(activity, android.R.layout.simple_list_item_1, names))
hadithList.onItemClick = function(l, v, p, i) showHadithPlayer(i + 1) end
end
function showHadithPlayer(bookIdx)
screen = "hadithplayer"
M.stopPlayer()
local b = hadithBooks()[bookIdx]
local localPath = M.getHadithLocal(b)
local playUrl = File(localPath).exists() and localPath or M.buildHadithUrl(b)
local isDownloaded = File(localPath).exists()
local bgColor, textColor = M.getThemeColors()
activity.setContentView(loadlayout{
LinearLayout, id="mainLayout", orientation=1, padding="20dp", layout_width=-1, layout_height=-1, gravity="center", backgroundColor=bgColor,
{TextView, text=(isDownloaded and "Offline Mode" or "Online Stream"), textSize="14sp", layout_marginBottom="10dp", textColor=appColorStr},
{TextView, text="Book " .. b.n .. ": " .. b.title, textSize="20sp", typeface=Typeface.DEFAULT_BOLD, layout_marginBottom="5dp", textColor=appColorStr, gravity="center"},
{TextView, text=b.range .. " of 7563", textSize="13sp", textColor=textColor, layout_marginBottom="20dp"},
{SeekBar, id="hdSeekBar", layout_width=-1, layout_marginBottom="10dp"},
{LinearLayout, orientation=0, layout_width=-1, gravity="center", layout_marginBottom="10dp",
{TextView, id="hdCurrentTxt", text="00:00", layout_weight=1, gravity="center"},
{TextView, id="hdTotalTxt", text="00:00", layout_weight=1, gravity="center"}
},
{LinearLayout, orientation=0, gravity="center", layout_width=-1,
{Button, id="hdPrevBtn", text="⏮", textSize="14sp", layout_weight=1, layout_margin="2dp"},
{Button, id="hdRwdBtn", text="⏪ "..seekSeconds.."s", textSize="16sp", layout_weight=1, layout_margin="2dp"},
{Button, id="hdPlayPause", text="▶ " .. tr("Play"), textSize="16sp", typeface=Typeface.DEFAULT_BOLD, layout_weight=1.5, layout_margin="2dp"},
{Button, id="hdFwdBtn", text=seekSeconds.."s ⏩", textSize="16sp", layout_weight=1, layout_margin="2dp"},
{Button, id="hdNextBtn", text="⏭", textSize="14sp", layout_weight=1, layout_margin="2dp"}
},
{Button, id="hdDownload", text=isDownloaded and "🗑 Delete Offline" or "⬇️ Download", textSize="14sp", layout_width=-1, layout_marginTop="20dp", backgroundColor=isDownloaded and "#C62828" or "#1976D2", textColor=-1},
{LinearLayout, orientation=0, gravity="center", layout_marginTop="30dp", layout_width=-1,
{Button, text="Book List", layout_weight=1, layout_marginRight="10dp", onClick=function() safeRun("showHadithScreen", showHadithScreen) end},
{Button, text="Exit App", layout_weight=1, backgroundColor="#C62828", textColor=-1, onClick=function() activity.finish() end}
}
})
M.applyWallpaper(mainLayout, bgColor)
hdPrevBtn.onClick = function() if bookIdx > 1 then showHadithPlayer(bookIdx - 1) end end
hdNextBtn.onClick = function() if bookIdx < #hadithBooks() then showHadithPlayer(bookIdx + 1) end end
hdRwdBtn.onClick = function()
if duaMp then pcall(function()
local np = duaMp.getCurrentPosition() - (seekSeconds*1000)
duaMp.seekTo(np > 0 and np or 0)
end) end
end
hdFwdBtn.onClick = function()
if duaMp then pcall(function()
local np = duaMp.getCurrentPosition() + (seekSeconds*1000)
if np < duaMp.getDuration() then duaMp.seekTo(np) end
end) end
end
hdPlayPause.onClick = function()
if duaMp then
pcall(function()
if duaMp.isPlaying() then
duaMp.pause()
hdPlayPause.setText("▶ " .. tr("Play"))
else
duaMp.start()
hdPlayPause.setText("⏸ " .. tr("Pause"))
end
end)
else
hdPlayPause.setText("Loading...")
M.playReliable(playUrl, localPath, "Bukhari Book " .. b.n, nil, function()
pcall(function() hdPlayPause.setText("▶ " .. tr("Play")) end)
if bookIdx < #hadithBooks() then showHadithPlayer(bookIdx + 1) end
end)
end
end
hdDownload.onClick = function()
if File(localPath).exists() then
confirmDelete(localPath, function() showHadithPlayer(bookIdx) end)
else
local ok, err = pcall(function()
local req = DownloadManager.Request(Uri.parse(M.buildHadithUrl(b)))
req.setTitle("Bukhari Book " .. b.n .. ": " .. b.title)
req.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
req.setDestinationUri(Uri.fromFile(File(localPath)))
activity.getSystemService(Context.DOWNLOAD_SERVICE).enqueue(req)
end)
if ok then
Toast.makeText(activity, "Download shuru ho gaya...", 1).show()
else
showErrorDialog("Hadith Download Error", err)
end
end
end
updateTask = Runnable({run = function()
if duaMp then pcall(function()
if duaMp.isPlaying() then
hdSeekBar.setMax(duaMp.getDuration())
hdSeekBar.setProgress(duaMp.getCurrentPosition())
hdCurrentTxt.setText(ft(duaMp.getCurrentPosition()))
hdTotalTxt.setText(ft(duaMp.getDuration()))
end
end) end
handler.postDelayed(updateTask, 1000)
end})
handler.post(updateTask)
hdSeekBar.setOnSeekBarChangeListener(SeekBar.OnSeekBarChangeListener{onProgressChanged=function(s, p, f) if f and duaMp then pcall(function() duaMp.seekTo(p) end) end end})
end
function showIsrarTafseerScreen()
screen = "israrlist"
M.stopPlayer()
local bgColor, textColor = M.getThemeColors()
local names = {}
for _, t in ipairs(M.israrTafseerFiles()) do table.insert(names, t.n == 0 and t.title or ("Surah " .. t.n .. ": " .. t.title)) end
activity.setContentView(loadlayout{
LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor,
{LinearLayout, orientation=0, padding="10dp", backgroundColor="#5D4037", layout_width=-1, gravity="center_vertical",
{Button, text=tr("Back"), onClick=function() safeRun("showMore", showMore) end},
{TextView, text="Tafseer-e-Quran (Dr. Israr Ahmad)", textSize="15sp", typeface=Typeface.DEFAULT_BOLD, layout_marginLeft="10dp", textColor=-1}
},
{TextView, text="Bayan-ul-Quran - Introduction + 114 Surah, Urdu mein", textSize="12sp", textColor="#777777", padding="8dp"},
{ListView, id="israrList", layout_width=-1, layout_height=0, layout_weight=1}
})
M.applyWallpaper(mainLayout, bgColor)
israrList.setAdapter(ArrayAdapter(activity, android.R.layout.simple_list_item_1, names))
israrList.onItemClick = function(l, v, p, i) showIsrarTafseerPlayer(i + 1) end
end
function showIsrarTafseerPlayer(idx)
screen = "israrplayer"
M.stopPlayer()
local t = M.israrTafseerFiles()[idx]
local localPath = M.getIsrarTafseerLocal(t)
local playUrl = File(localPath).exists() and localPath or M.buildIsrarTafseerUrl(t)
local isDownloaded = File(localPath).exists()
local bgColor, textColor = M.getThemeColors()
activity.setContentView(loadlayout{
LinearLayout, id="mainLayout", orientation=1, padding="20dp", layout_width=-1, layout_height=-1, gravity="center", backgroundColor=bgColor,
{TextView, text=(isDownloaded and "Offline Mode" or "Online Stream"), textSize="14sp", layout_marginBottom="10dp", textColor=appColorStr},
{TextView, text=t.n == 0 and t.title or ("Surah " .. t.n .. ": " .. t.title), textSize="18sp", typeface=Typeface.DEFAULT_BOLD, layout_marginBottom="20dp", textColor=appColorStr, gravity="center"},
{SeekBar, id="izSeekBar", layout_width=-1, layout_marginBottom="10dp"},
{LinearLayout, orientation=0, layout_width=-1, gravity="center", layout_marginBottom="10dp",
{TextView, id="izCurrentTxt", text="00:00", layout_weight=1, gravity="center"},
{TextView, id="izTotalTxt", text="00:00", layout_weight=1, gravity="center"}
},
{LinearLayout, orientation=0, gravity="center", layout_width=-1,
{Button, id="izPrevBtn", text="⏮", textSize="14sp", layout_weight=1, layout_margin="2dp"},
{Button, id="izRwdBtn", text="⏪ "..seekSeconds.."s", textSize="16sp", layout_weight=1, layout_margin="2dp"},
{Button, id="izPlayPause", text="▶ " .. tr("Play"), textSize="16sp", typeface=Typeface.DEFAULT_BOLD, layout_weight=1.5, layout_margin="2dp"},
{Button, id="izFwdBtn", text=seekSeconds.."s ⏩", textSize="16sp", layout_weight=1, layout_margin="2dp"},
{Button, id="izNextBtn", text="⏭", textSize="14sp", layout_weight=1, layout_margin="2dp"}
},
{Button, id="izDownload", text=isDownloaded and "🗑 Delete Offline" or "⬇️ Download", textSize="14sp", layout_width=-1, layout_marginTop="20dp", backgroundColor=isDownloaded and "#C62828" or "#1976D2", textColor=-1},
{LinearLayout, orientation=0, gravity="center", layout_marginTop="30dp", layout_width=-1,
{Button, text="List", layout_weight=1, layout_marginRight="10dp", onClick=function() safeRun("showIsrarTafseerScreen", showIsrarTafseerScreen) end},
{Button, text="Exit App", layout_weight=1, backgroundColor="#C62828", textColor=-1, onClick=function() activity.finish() end}
}
})
M.applyWallpaper(mainLayout, bgColor)
izPrevBtn.onClick = function() if idx > 1 then showIsrarTafseerPlayer(idx - 1) end end
izNextBtn.onClick = function() if idx < #M.israrTafseerFiles() then showIsrarTafseerPlayer(idx + 1) end end
izRwdBtn.onClick = function()
if duaMp then pcall(function()
local np = duaMp.getCurrentPosition() - (seekSeconds*1000)
duaMp.seekTo(np > 0 and np or 0)
end) end
end
izFwdBtn.onClick = function()
if duaMp then pcall(function()
local np = duaMp.getCurrentPosition() + (seekSeconds*1000)
if np < duaMp.getDuration() then duaMp.seekTo(np) end
end) end
end
izPlayPause.onClick = function()
if duaMp then
pcall(function()
if duaMp.isPlaying() then
duaMp.pause()
izPlayPause.setText("▶ " .. tr("Play"))
else
duaMp.start()
izPlayPause.setText("⏸ " .. tr("Pause"))
end
end)
else
izPlayPause.setText("Loading...")
M.playReliable(playUrl, localPath, t.title, nil, function()
pcall(function() izPlayPause.setText("▶ " .. tr("Play")) end)
if idx < #M.israrTafseerFiles() then showIsrarTafseerPlayer(idx + 1) end
end)
end
end
izDownload.onClick = function()
if File(localPath).exists() then
confirmDelete(localPath, function() showIsrarTafseerPlayer(idx) end)
else
local ok, err = pcall(function()
local req = DownloadManager.Request(Uri.parse(M.buildIsrarTafseerUrl(t)))
req.setTitle(t.title)
req.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
req.setDestinationUri(Uri.fromFile(File(localPath)))
activity.getSystemService(Context.DOWNLOAD_SERVICE).enqueue(req)
end)
if ok then
Toast.makeText(activity, "Download shuru ho gaya...", 1).show()
else
showErrorDialog("Tafseer Download Error", err)
end
end
end
updateTask = Runnable({run = function()
if duaMp then pcall(function()
if duaMp.isPlaying() then
izSeekBar.setMax(duaMp.getDuration())
izSeekBar.setProgress(duaMp.getCurrentPosition())
izCurrentTxt.setText(ft(duaMp.getCurrentPosition()))
izTotalTxt.setText(ft(duaMp.getDuration()))
end
end) end
handler.postDelayed(updateTask, 1000)
end})
handler.post(updateTask)
izSeekBar.setOnSeekBarChangeListener(SeekBar.OnSeekBarChangeListener{onProgressChanged=function(s, p, f) if f and duaMp then pcall(function() duaMp.seekTo(p) end) end end})
end
function showNawawiScreen()
screen = "nawawilist"
M.stopPlayer()
local bgColor, textColor = M.getThemeColors()
local names = {}
for i = 1, 40 do table.insert(names, "Hadith " .. i) end
activity.setContentView(loadlayout{
LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor,
{LinearLayout, orientation=0, padding="10dp", backgroundColor="#3E2723", layout_width=-1, gravity="center_vertical",
{Button, text=tr("Back"), onClick=function() safeRun("showMore", showMore) end},
{TextView, text="40 Hadith (Imam An-Nawawi)", textSize="15sp", typeface=Typeface.DEFAULT_BOLD, layout_marginLeft="10dp", textColor=-1}
},
{TextView, text="Mukhtasar, mash-hoor 40 Ahadith ka majmua", textSize="12sp", textColor="#777777", padding="8dp"},
{ListView, id="nawawiList", layout_width=-1, layout_height=0, layout_weight=1}
})
M.applyWallpaper(mainLayout, bgColor)
nawawiList.setAdapter(ArrayAdapter(activity, android.R.layout.simple_list_item_1, names))
nawawiList.onItemClick = function(l, v, p, i) showNawawiPlayer(i + 1) end
end
function showNawawiPlayer(n)
screen = "nawawiplayer"
M.stopPlayer()
local localPath = M.getNawawiLocal(n)
local playUrl = File(localPath).exists() and localPath or M.buildNawawiUrl(n)
local isDownloaded = File(localPath).exists()
local bgColor, textColor = M.getThemeColors()
activity.setContentView(loadlayout{
LinearLayout, id="mainLayout", orientation=1, padding="20dp", layout_width=-1, layout_height=-1, gravity="center", backgroundColor=bgColor,
{TextView, text=(isDownloaded and "Offline Mode" or "Online Stream"), textSize="14sp", layout_marginBottom="10dp", textColor=appColorStr},
{TextView, text="Hadith " .. n .. " of 40", textSize="20sp", typeface=Typeface.DEFAULT_BOLD, layout_marginBottom="20dp", textColor=appColorStr, gravity="center"},
{SeekBar, id="nwSeekBar", layout_width=-1, layout_marginBottom="10dp"},
{LinearLayout, orientation=0, layout_width=-1, gravity="center", layout_marginBottom="10dp",
{TextView, id="nwCurrentTxt", text="00:00", layout_weight=1, gravity="center"},
{TextView, id="nwTotalTxt", text="00:00", layout_weight=1, gravity="center"}
},
{LinearLayout, orientation=0, gravity="center", layout_width=-1,
{Button, id="nwPrevBtn", text="⏮", textSize="14sp", layout_weight=1, layout_margin="2dp"},
{Button, id="nwRwdBtn", text="⏪ "..seekSeconds.."s", textSize="16sp", layout_weight=1, layout_margin="2dp"},
{Button, id="nwPlayPause", text="▶ " .. tr("Play"), textSize="16sp", typeface=Typeface.DEFAULT_BOLD, layout_weight=1.5, layout_margin="2dp"},
{Button, id="nwFwdBtn", text=seekSeconds.."s ⏩", textSize="16sp", layout_weight=1, layout_margin="2dp"},
{Button, id="nwNextBtn", text="⏭", textSize="14sp", layout_weight=1, layout_margin="2dp"}
},
{Button, id="nwDownload", text=isDownloaded and "🗑 Delete Offline" or "⬇️ Download", textSize="14sp", layout_width=-1, layout_marginTop="20dp", backgroundColor=isDownloaded and "#C62828" or "#1976D2", textColor=-1},
{LinearLayout, orientation=0, gravity="center", layout_marginTop="30dp", layout_width=-1,
{Button, text="List", layout_weight=1, layout_marginRight="10dp", onClick=function() safeRun("showNawawiScreen", showNawawiScreen) end},
{Button, text="Exit App", layout_weight=1, backgroundColor="#C62828", textColor=-1, onClick=function() activity.finish() end}
}
})
M.applyWallpaper(mainLayout, bgColor)
nwPrevBtn.onClick = function() if n > 1 then showNawawiPlayer(n - 1) end end
nwNextBtn.onClick = function() if n < 40 then showNawawiPlayer(n + 1) end end
nwRwdBtn.onClick = function()
if duaMp then pcall(function()
local np = duaMp.getCurrentPosition() - (seekSeconds*1000)
duaMp.seekTo(np > 0 and np or 0)
end) end
end
nwFwdBtn.onClick = function()
if duaMp then pcall(function()
local np = duaMp.getCurrentPosition() + (seekSeconds*1000)
if np < duaMp.getDuration() then duaMp.seekTo(np) end
end) end
end
nwPlayPause.onClick = function()
if duaMp then
pcall(function()
if duaMp.isPlaying() then
duaMp.pause()
nwPlayPause.setText("▶ " .. tr("Play"))
else
duaMp.start()
nwPlayPause.setText("⏸ " .. tr("Pause"))
end
end)
else
nwPlayPause.setText("Loading...")
M.playReliable(playUrl, localPath, "Hadith " .. n, nil, function()
pcall(function() nwPlayPause.setText("▶ " .. tr("Play")) end)
if n < 40 then showNawawiPlayer(n + 1) end
end)
end
end
nwDownload.onClick = function()
if File(localPath).exists() then
confirmDelete(localPath, function() showNawawiPlayer(n) end)
else
local ok, err = pcall(function()
local req = DownloadManager.Request(Uri.parse(M.buildNawawiUrl(n)))
req.setTitle("Hadith " .. n)
req.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
req.setDestinationUri(Uri.fromFile(File(localPath)))
activity.getSystemService(Context.DOWNLOAD_SERVICE).enqueue(req)
end)
if ok then
Toast.makeText(activity, "Download shuru ho gaya...", 1).show()
else
showErrorDialog("Hadith Download Error", err)
end
end
end
updateTask = Runnable({run = function()
if duaMp then pcall(function()
if duaMp.isPlaying() then
nwSeekBar.setMax(duaMp.getDuration())
nwSeekBar.setProgress(duaMp.getCurrentPosition())
nwCurrentTxt.setText(ft(duaMp.getCurrentPosition()))
nwTotalTxt.setText(ft(duaMp.getDuration()))
end
end) end
handler.postDelayed(updateTask, 1000)
end})
handler.post(updateTask)
nwSeekBar.setOnSeekBarChangeListener(SeekBar.OnSeekBarChangeListener{onProgressChanged=function(s, p, f) if f and duaMp then pcall(function() duaMp.seekTo(p) end) end end})
end
function showMore()
screen = "more"
local bgColor, textColor = M.getThemeColors()
activity.setContentView(loadlayout{
LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor,
{ScrollView, layout_width=-1, layout_height=0, layout_weight=1,
{LinearLayout, orientation=1, padding="20dp", layout_width=-1, layout_height=-2,
{TextView, text="More", textSize="24sp", typeface=Typeface.DEFAULT_BOLD, layout_marginBottom="20dp", textColor=appColorStr},
{Button, text="30 Para", textSize="18sp", layout_width=-1, layout_marginBottom="15dp", backgroundColor="#2E7D32", textColor=-1, onClick=function() safeRun("showPara", showPara) end},
{Button, text="Digital Tasbeeh", textSize="18sp", layout_width=-1, layout_marginBottom="15dp", backgroundColor="#00796B", textColor=-1, onClick=function() safeRun("showTasbeeh", showTasbeeh) end},
{Button, text="Bookmarks", textSize="18sp", layout_width=-1, layout_marginBottom="15dp", backgroundColor="#E91E63", textColor=-1, onClick=function() safeRun("showBookmarksScreen", showBookmarksScreen) end},
{Button, text="99 Names of Allah", textSize="18sp", layout_width=-1, layout_marginBottom="15dp", backgroundColor="#8E24AA", textColor=-1, onClick=function() safeRun("showNamesOfAllah", showNamesOfAllah) end},
{Button, text="Blessed Names of Prophet", textSize="18sp", layout_width=-1, layout_marginBottom="15dp", backgroundColor="#00695C", textColor=-1, onClick=function() safeRun("showAsmaNabi", showAsmaNabi) end},
{Button, text="Poori Quran (Continuous)", textSize="18sp", layout_width=-1, layout_marginBottom="15dp", backgroundColor="#3E2723", textColor=-1, onClick=function() safeRun("showFullQuranScreen", showFullQuranScreen) end},
{Button, text="Hadith (Sahih Bukhari)", textSize="18sp", layout_width=-1, layout_marginBottom="15dp", backgroundColor="#4E342E", textColor=-1, onClick=function() safeRun("showHadithScreen", showHadithScreen) end},
{Button, text="Tafseer-e-Quran (Dr. Israr Ahmad)", textSize="18sp", layout_width=-1, layout_marginBottom="15dp", backgroundColor="#5D4037", textColor=-1, onClick=function() safeRun("showIsrarTafseerScreen", showIsrarTafseerScreen) end},
{Button, text="40 Hadith (An-Nawawi)", textSize="18sp", layout_width=-1, layout_marginBottom="15dp", backgroundColor="#3E2723", textColor=-1, onClick=function() safeRun("showNawawiScreen", showNawawiScreen) end},
{Button, text="Adhan Audio", textSize="18sp", layout_width=-1, layout_marginBottom="15dp", backgroundColor="#00695C", textColor=-1, contentDescription="Open Adhan recordings to play or download", onClick=function() safeRun("showAzan", showAzan) end},
{Button, text="6 Kalme / Iman / Namaz Audio", textSize="18sp", layout_width=-1, layout_marginBottom="15dp", backgroundColor="#00695C", textColor=-1, contentDescription="Six Kalimas, Iman e Mufassal, Iman e Mujmal, Namaz ka Sabaq aur Namaz e Janaza audio", onClick=function() safeRun("showKalimaImanScreen", showKalimaImanScreen) end},
{Button, text="📚 اسلامک بکس / Islam Books (Urdu, English, Arabic, Punjabi)", textSize="15sp", layout_width=-1, layout_margin="5dp", onClick=function() safeRun("showUrduBooks", showUrduBooks) end},
{Button, text="🔊 نعتیں / Naats (14 Collections)", textSize="15sp", layout_width=-1, layout_margin="5dp", onClick=function() safeRun("showNaats", function() showBookCatScreen("naat") end) end},
{Button, text="🎤 بیانات / Bayanat (12 Collections)", textSize="15sp", layout_width=-1, layout_margin="5dp", onClick=function() safeRun("showBayanat", function() showBookCatScreen("bayan") end) end},
{Button, text="🔎 Advanced Search", textSize="15sp", layout_width=-1, layout_margin="5dp", onClick=function() safeRun("showAdvancedSearch", showAdvancedSearch) end},
{Button, text="Menu", textSize="18sp", layout_width=-1, layout_marginBottom="15dp", onClick=function() safeRun("showSettings", showSettings) end}
}},
M.moreSubTabs("")
})
M.applyWallpaper(mainLayout, bgColor)
end
function showTasbeeh()
screen = "tasbeeh"
local targets = {33, 34, 99, 100, 1000, 5000, 10000, 100000, 9999999}
local targetLabels = {"Target: 33", "Target: 34", "Target: 99", "Target: 100", "Target: 1,000", "Target: 5,000", "Target: 10,000", "Target: 100,000", "Unlimited (No Limit)"}
local targetIndex = 0
for i,v in ipairs(targets) do if v == tasbeehTarget then targetIndex = i - 1 break end end
local bgColor, textColor = M.getThemeColors()
activity.setContentView(loadlayout{
ScrollView, layout_width=-1, layout_height=-1, fillViewport=true, backgroundColor=bgColor,
{LinearLayout, id="mainLayout", orientation=1, padding="20dp", layout_width=-1, layout_height=-1, gravity="center_horizontal",
{LinearLayout, orientation=0, layout_width=-1, gravity="center_vertical", layout_marginBottom="10dp",
{Button, text=tr("Back"), onClick=function() safeRun("showMore", showMore) end},
{TextView, text=tr("Digital Tasbeeh"), textSize="22sp", typeface=Typeface.DEFAULT_BOLD, layout_marginLeft="15dp", textColor=textColor}
},
{LinearLayout, orientation=0, layout_width=-1, gravity="center", layout_marginBottom="15dp", padding="10dp", backgroundColor="#1A000000",
{TextView, text="🌟 " .. tr("Lifetime Zikr:"), textSize="16sp", typeface=Typeface.DEFAULT_BOLD, textColor=appColorStr, layout_weight=1},
{TextView, id="txtLifetime", text=tostring(lifetimeZikrTotal), textSize="18sp", typeface=Typeface.DEFAULT_BOLD, textColor=textColor}
},
{LinearLayout, orientation=0, layout_width=-1, gravity="center", layout_marginBottom="15dp",
{CheckBox, id="chkSound", text="🔊", textSize="16sp", checked=tasbeehBeepEnabled, textColor=textColor, layout_marginRight="10dp"},
{CheckBox, id="chkVib", text="📳", textSize="16sp", checked=tasbeehVibrateEnabled, textColor=textColor, layout_marginRight="10dp"},
{CheckBox, id="chkAwake", text="💡 Awake", textSize="16sp", checked=false, textColor=textColor}
},
{TextView, text=tr("Select Category:"), textSize="14sp", textColor=textColor, layout_width=-1, gravity="left", layout_marginBottom="5dp"},
{Spinner, id="categorySpinner", layout_width=-1, layout_marginBottom="10dp"},
{TextView, text="Select Wazeefa:", textSize="14sp", textColor=textColor, layout_width=-1, gravity="left", layout_marginBottom="5dp"},
{Spinner, id="wazeefaSpinner", layout_width=-1, layout_marginBottom="10dp"},
{TextView, id="txtWazeefaDisplay", text=wazaifArabicText[currentWazeefaIndex + 1], textSize="26sp", typeface=Typeface.DEFAULT_BOLD, textColor=appColorStr, gravity="center", layout_marginBottom="10dp"},
{Spinner, id="targetSpinner", layout_width="200dp", layout_marginBottom="10dp"},
{ProgressBar, id="tasbeehProgress", style="?android:attr/progressBarStyleHorizontal", layout_width=-1, layout_marginBottom="15dp", max=tasbeehTarget, progress=tasbeehCount},
{TextView, id="txtCount", text=tostring(tasbeehCount), textSize="80sp", typeface=Typeface.DEFAULT_BOLD, textColor=appColorStr, layout_marginBottom="20dp"},
{Button, id="btnTap", text="TAP", textSize="36sp", typeface=Typeface.DEFAULT_BOLD, layout_width="200dp", layout_height="200dp", backgroundColor="#4CAF50", textColor=-1},
{LinearLayout, orientation=1, layout_width=-1, layout_marginTop="20dp",
{LinearLayout, orientation=0, layout_width=-1, layout_marginBottom="5dp",
{Button, id="btnSave", text="💾 " .. tr("Save"), textSize="14sp", layout_weight=1, layout_marginRight="5dp", backgroundColor="#1976D2", textColor=-1},
{Button, id="btnRecent", text="🔁 " .. tr("Recent"), textSize="14sp", layout_weight=1, layout_marginLeft="5dp", backgroundColor="#FF8F00", textColor=-1}
},
{LinearLayout, orientation=0, layout_width=-1,
{Button, id="btnClearSaved", text="🧹 " .. tr("Clear"), textSize="14sp", layout_weight=1, layout_marginRight="5dp", backgroundColor="#757575", textColor=-1},
{Button, id="btnReset", text="❌ " .. tr("Reset"), textSize="14sp", layout_weight=1, layout_marginLeft="5dp", backgroundColor="#C62828", textColor=-1}
}
}
}
})
M.applyWallpaper(mainLayout, bgColor)
chkSound.setOnCheckedChangeListener(CompoundButton.OnCheckedChangeListener{onCheckedChanged=function(b, isChecked) tasbeehBeepEnabled=isChecked M.saveActiveTasbeehState() end})
chkVib.setOnCheckedChangeListener(CompoundButton.OnCheckedChangeListener{onCheckedChanged=function(b, isChecked) tasbeehVibrateEnabled=isChecked M.saveActiveTasbeehState() end})
chkAwake.setOnCheckedChangeListener(CompoundButton.OnCheckedChangeListener{onCheckedChanged=function(b, isChecked)
if isChecked then activity.getWindow().addFlags(128) else activity.getWindow().clearFlags(128) end
end})
categorySpinner.setAdapter(ArrayAdapter(activity, android.R.layout.simple_spinner_dropdown_item, wazaifCategories))
wazeefaSpinner.setAdapter(ArrayAdapter(activity, android.R.layout.simple_spinner_dropdown_item, wazaifLabels))
wazeefaSpinner.setSelection(currentWazeefaIndex)
wazeefaSpinner.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{onItemSelected=function(p, v, pos, id) currentWazeefaIndex=pos txtWazeefaDisplay.setText(wazaifArabicText[pos+1]) M.saveActiveTasbeehState() end})
targetSpinner.setAdapter(ArrayAdapter(activity, android.R.layout.simple_spinner_dropdown_item, targetLabels))
targetSpinner.setSelection(targetIndex)
targetSpinner.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{onItemSelected=function(p, v, pos, id) tasbeehTarget=targets[pos+1] tasbeehProgress.setMax(tasbeehTarget) if tasbeehTarget==9999999 then tasbeehProgress.setMax(100) tasbeehProgress.setProgress(100) end M.saveActiveTasbeehState() end})
btnTap.onClick = function()
if tasbeehVibrateEnabled then M.doVibrate(30) end
tasbeehCount = tasbeehCount + 1
lifetimeZikrTotal = lifetimeZikrTotal + 1
txtCount.setText(tostring(tasbeehCount))
txtLifetime.setText(tostring(lifetimeZikrTotal))
prefs.edit().putInt("lifetimeZikrTotal", lifetimeZikrTotal).apply()
if tasbeehTarget ~= 9999999 then tasbeehProgress.setProgress(tasbeehCount) end
M.saveActiveTasbeehState()
if tasbeehCount == tasbeehTarget and tasbeehTarget ~= 9999999 then
if tasbeehBeepEnabled then M.playBeep() end if tasbeehVibrateEnabled then M.doVibrate(500) end
Toast.makeText(activity, "MashAllah! Target Reached", 1).show()
end
end
btnSave.onClick = function() prefs.edit().putInt("savedCount", tasbeehCount).putInt("savedTarget", tasbeehTarget).putInt("savedWazeefa", currentWazeefaIndex).apply() Toast.makeText(activity, "Tasbeeh Saved!", 0).show() end
btnRecent.onClick = function()
local sCount = prefs.getInt("savedCount", -1)
if sCount == -1 then Toast.makeText(activity, "No saved data!", 0).show() else
tasbeehCount=sCount tasbeehTarget=prefs.getInt("savedTarget", 33) currentWazeefaIndex=prefs.getInt("savedWazeefa", 0)
txtCount.setText(tostring(tasbeehCount)) txtWazeefaDisplay.setText(wazaifArabicText[currentWazeefaIndex + 1])
wazeefaSpinner.setSelection(currentWazeefaIndex)
for i,v in ipairs(targets) do if v == tasbeehTarget then targetSpinner.setSelection(i - 1) break end end
if tasbeehTarget ~= 9999999 then tasbeehProgress.setMax(tasbeehTarget) tasbeehProgress.setProgress(tasbeehCount) end
M.saveActiveTasbeehState()
end
end
btnClearSaved.onClick = function() prefs.edit().remove("savedCount").remove("savedTarget").remove("savedWazeefa").apply() Toast.makeText(activity, "Saved Data Cleared!", 0).show() end
btnReset.onClick = function() tasbeehCount=0 txtCount.setText("0") tasbeehProgress.setProgress(0) M.saveActiveTasbeehState() if tasbeehVibrateEnabled then M.doVibrate(50) end end
end
function showSurahList()
screen = "surahlist"
local bgColor, textColor = M.getThemeColors()
local filteredSurahs = {} local filteredIndices = {}
for i,v in ipairs(surahNames) do
if not deletedSurahs[i] and pinned[i] then table.insert(filteredSurahs, "📌 " .. v) table.insert(filteredIndices, i) end
end
for i,v in ipairs(surahNames) do
if not deletedSurahs[i] and not pinned[i] then table.insert(filteredSurahs, v) table.insert(filteredIndices, i) end
end
activity.setContentView(loadlayout{
LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor,
{LinearLayout, orientation=0, padding="10dp", backgroundColor=appColorStr, layout_width=-1, gravity="center_vertical",
{Button, text=tr("Back"), onClick=function() safeRun("showHome", showHome) end},
{TextView, text="Quran Pak (use the search bar on Home to find a Surah)", textSize="14sp", layout_marginLeft="10dp", textColor=-1}
},
{ListView, id="list", layout_width=-1, layout_height=0, layout_weight=1},
M.bottomTabs("quran")
})
M.applyWallpaper(mainLayout, bgColor)
local adapter = ArrayAdapter(activity, android.R.layout.simple_list_item_1, filteredSurahs)
list.setAdapter(adapter)
list.onItemClick = function(l, v, p, i) currentIndex = filteredIndices[i + 1] showPlayer(currentIndex) end
list.onItemLongClick = function(l, v, p, i)
local sIndex = filteredIndices[i + 1]
local sName = surahNames[sIndex]
AlertDialog.Builder(activity).setTitle(sName).setItems({"▶️ Play", "🔖 Bookmark", "📌 Pin", "📋 Copy", "🗑️ Delete", "❌ Cancel"}, {onClick=function(dialog, which)
if which == 0 then currentIndex = sIndex showPlayer(currentIndex)
elseif which == 1 then table.insert(bookmarks, sIndex) M.saveBookmarks() Toast.makeText(activity, "Bookmarked!", 0).show()
elseif which == 2 then pinned[sIndex] = not pinned[sIndex] M.savePinned() showSurahList()
elseif which == 3 then activity.getSystemService(Context.CLIPBOARD_SERVICE).setPrimaryClip(ClipData.newPlainText("Surah", sName)) Toast.makeText(activity, "Copied!", 0).show()
elseif which == 4 then deletedSurahs[sIndex] = true M.saveDeleted() showSurahList()
end
end}).show()
return true
end
end
function showBookmarksScreen()
screen = "bookmarks"
local bgColor, textColor = M.getThemeColors()
local filteredBms = {} local filteredIndices = {}
local function loadBm(query)
filteredBms = {} filteredIndices = {}
for i,v in ipairs(bookmarks) do
local sName = surahNames[v]
if sName:lower():find(query) or query == "" then table.insert(filteredBms, sName) table.insert(filteredIndices, v) end
end
end
loadBm("")
activity.setContentView(loadlayout{
LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor,
{LinearLayout, orientation=0, padding="10dp", backgroundColor=appColorStr, layout_width=-1, gravity="center_vertical",
{Button, text=tr("Back"), onClick=function() safeRun("showMore", showMore) end},
{EditText, id="etSearchBm", hint="Search Bookmarks...", layout_marginLeft="10dp", layout_weight=1, singleLine=true, textColor=-1, hintTextColor="#DDDDDD"},
{Button, text="🗑️ Clear", layout_marginLeft="5dp", onClick=function() bookmarks = {} M.saveBookmarks() showBookmarksScreen() end}
},
{ListView, id="bmList", layout_width=-1, layout_height=-1}
})
M.applyWallpaper(mainLayout, bgColor)
local adapter = ArrayAdapter(activity, android.R.layout.simple_list_item_1, filteredBms)
bmList.setAdapter(adapter)
etSearchBm.addTextChangedListener(TextWatcher{onTextChanged=function(c) loadBm(tostring(c):lower()) adapter = ArrayAdapter(activity, android.R.layout.simple_list_item_1, filteredBms) bmList.setAdapter(adapter) end})
bmList.onItemClick = function(l, v, p, i) M.hideKeyboard(etSearchBm) if #bookmarks > 0 then currentIndex = filteredIndices[i + 1] showPlayer(currentIndex) end end
bmList.onItemLongClick = function(l, v, p, i)
M.hideKeyboard(etSearchBm)
if #bookmarks > 0 then
local realIndex = filteredIndices[i+1]
AlertDialog.Builder(activity).setTitle("Options").setItems({"▶️ Play", "🔖 Remove", "❌ Cancel"}, {onClick=function(d, w)
if w == 0 then currentIndex = realIndex showPlayer(currentIndex)
elseif w == 1 then for idx, val in ipairs(bookmarks) do if val == realIndex then table.remove(bookmarks, idx) break end end M.saveBookmarks() showBookmarksScreen() end
end}).show()
end return true
end
end
function showSettings()
screen = "settings"
local bgColor, textColor = M.getThemeColors()
local reciterNames = {} for i, v in ipairs(reciters) do table.insert(reciterNames, v.name) end
local speedLabels = {"0.75x", "1.0x (Normal)", "1.25x", "1.5x", "2.0x"} local speedValues = {0.75, 1.0, 1.25, 1.5, 2.0}
local speedIndex = 1 for i,v in ipairs(speedValues) do if v == PS.speed then speedIndex = i - 1 break end end
local sleepLabels = {"Off", "15 Minutes", "30 Minutes", "45 Minutes", "60 Minutes"} local sleepValues = {0, 15, 30, 45, 60}
local sleepIndex = 0 for i,v in ipairs(sleepValues) do if v == sleepTimerMinutes then sleepIndex = i - 1 break end end
local seekLabels = {"5 Seconds", "10 Seconds", "15 Seconds", "20 Seconds", "25 Seconds", "30 Seconds", "1 Minute"} local seekValues = {5, 10, 15, 20, 25, 30, 60}
local seekIndex = 1 for i,v in ipairs(seekValues) do if v == seekSeconds then seekIndex = i - 1 break end end
local tarjumaLabels = V25_TRANSLATION_LABELS
local tarjumaIndex = 0 for i,v in ipairs(tarjumaLabels) do if v == translationMode then tarjumaIndex = i - 1 break end end
local urduVoiceLabels = {"Shamshad Ali Khan", "Farhat Hashmi", "Kanzul Iman"}
local urduVoiceValues = {"Shamshad", "Farhat", "Kanzul"}
local urduVoiceIndex = 0 for i,v in ipairs(urduVoiceValues) do if v == urduVoice then urduVoiceIndex = i - 1 break end end
local farsiVoiceLabels = {"Fooladvand + Hedayatfar", "Makarem + Kabiri"}
local farsiVoiceValues = {"Fooladvand", "Makarem"}
local farsiVoiceIndex = (farsiVoice == "Makarem") and 1 or 0
local repeatLabels = {"1x (No Repeat)", "2x", "3x", "5x", "10x"} local repeatValues = {1, 2, 3, 5, 10}
local repeatIndex = 0 for i,v in ipairs(repeatValues) do if v == PS.ayahRepeat then repeatIndex = i - 1 break end end
activity.setContentView(loadlayout{
ScrollView, id="mainLayout", layout_width=-1, layout_height=-1, fillViewport=true, backgroundColor=bgColor,
{LinearLayout, orientation=1, padding="20dp", layout_width=-1, layout_height=-1,
{TextView, text="Menu", textSize="24sp", typeface=Typeface.DEFAULT_BOLD, layout_marginBottom="20dp", textColor=appColorStr},
{TextView, text="Select Reciter (DI + " .. (#reciters-1) .. " others):", textSize="16sp", textColor=textColor, typeface=Typeface.DEFAULT_BOLD},
{Spinner, id="reciterSpinner", layout_width=-1, layout_marginTop="5dp", layout_marginBottom="15dp"},
{TextView, text="Skip/Rewind Time:", textSize="16sp", textColor=textColor},
{Spinner, id="seekSpinner", layout_width=-1, layout_marginTop="5dp", layout_marginBottom="15dp"},
{TextView, text="Playback Speed:", textSize="16sp", textColor=textColor},
{Spinner, id="speedSpinner", layout_width=-1, layout_marginTop="5dp", layout_marginBottom="15dp"},
{TextView, text="Sleep Timer:", textSize="16sp", textColor=textColor},
{Spinner, id="sleepSpinner", layout_width=-1, layout_marginTop="5dp", layout_marginBottom="15dp"},
{TextView, text="Tarjuma (Translation):", textSize="16sp", textColor=textColor},
{Spinner, id="tarjumaSpinner", layout_width=-1, layout_marginTop="5dp", layout_marginBottom="15dp"},
{TextView, text="Urdu Tarjuma Awaz (jab Tarjuma=Urdu ho):", textSize="16sp", textColor=textColor},
{Spinner, id="urduVoiceSpinner", layout_width=-1, layout_marginTop="5dp", layout_marginBottom="15dp"},
{TextView, text="Farsi Ayah Tarjuma Awaz (jab Tarjuma=Farsi ho):", textSize="16sp", textColor=textColor},
{Spinner, id="farsiVoiceSpinner", layout_width=-1, layout_marginTop="5dp", layout_marginBottom="15dp"},
{TextView, text="Ayat Repeat Count (Ayat-ba-Ayat mode, hifz ke liye):", textSize="16sp", textColor=textColor},
{Spinner, id="repeatCountSpinner", layout_width=-1, layout_marginTop="5dp", layout_marginBottom="15dp"},
{TextView, text="App Preferences:", textSize="16sp", textColor=appColorStr, typeface=Typeface.DEFAULT_BOLD},
{CheckBox, id="chkAutoNext", text="Auto Next Surah Mode", textSize="16sp", layout_marginTop="10dp", checked=autoNextMode, textColor=textColor},
{Button, text="💬 " .. tr("Feedback & Support"), textSize="16sp", layout_width=-1, layout_marginTop="30dp", backgroundColor="#607D8B", textColor=-1, onClick=function() safeRun("showFeedback", showFeedback) end},
{Button, text="Social Media Support", textSize="16sp", layout_width=-1, layout_marginTop="10dp", backgroundColor="#00695C", textColor=-1, onClick=function() safeRun("showSocialMedia", showSocialMedia) end},
{Button, text="ℹ️ " .. tr("About App"), textSize="16sp", layout_width=-1, layout_marginTop="10dp", backgroundColor=appColorStr, textColor=-1, onClick=function() safeRun("showAbout", showAbout) end},
{LinearLayout, orientation=0, gravity="center", layout_marginTop="20dp", layout_width=-1,
{Button, text=tr("Back"), layout_weight=1, layout_marginRight="10dp", onClick=function() safeRun("showMore", showMore) end},
{Button, text="Exit App", layout_weight=1, backgroundColor="#C62828", textColor=-1, onClick=function() activity.finish() end}
}
}
})
M.applyWallpaper(mainLayout, bgColor)
reciterSpinner.setAdapter(ArrayAdapter(activity, android.R.layout.simple_spinner_dropdown_item, reciterNames))
reciterSpinner.setSelection(math.min(currentReciter, #reciters) - 1)
reciterSpinner.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{onItemSelected=function(p,v,pos,id) currentReciter=pos+1 end})
seekSpinner.setAdapter(ArrayAdapter(activity, android.R.layout.simple_spinner_dropdown_item, seekLabels)) seekSpinner.setSelection(seekIndex) seekSpinner.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{onItemSelected=function(p,v,pos,id) seekSeconds=seekValues[pos+1] end})
speedSpinner.setAdapter(ArrayAdapter(activity, android.R.layout.simple_spinner_dropdown_item, speedLabels)) speedSpinner.setSelection(speedIndex) speedSpinner.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{onItemSelected=function(p,v,pos,id) savePlaybackSpeed(speedValues[pos+1]) if mp then applyPlaybackSpeed(mp) end if duaMp then applyPlaybackSpeed(duaMp) end end})
sleepSpinner.setAdapter(ArrayAdapter(activity, android.R.layout.simple_spinner_dropdown_item, sleepLabels)) sleepSpinner.setSelection(sleepIndex) sleepSpinner.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{onItemSelected=function(p,v,pos,id) sleepTimerMinutes=sleepValues[pos+1] end})
tarjumaSpinner.setAdapter(ArrayAdapter(activity, android.R.layout.simple_spinner_dropdown_item, tarjumaLabels)) tarjumaSpinner.setSelection(tarjumaIndex) tarjumaSpinner.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{onItemSelected=function(p,v,pos,id) M.saveTranslationMode(tarjumaLabels[pos+1]) end})
urduVoiceSpinner.setAdapter(ArrayAdapter(activity, android.R.layout.simple_spinner_dropdown_item, urduVoiceLabels)) urduVoiceSpinner.setSelection(urduVoiceIndex) urduVoiceSpinner.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{onItemSelected=function(p,v,pos,id) M.saveUrduVoice(urduVoiceValues[pos+1]) end})
farsiVoiceSpinner.setAdapter(ArrayAdapter(activity, android.R.layout.simple_spinner_dropdown_item, farsiVoiceLabels)) farsiVoiceSpinner.setSelection(farsiVoiceIndex) farsiVoiceSpinner.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{onItemSelected=function(p,v,pos,id) M.saveFarsiVoice(farsiVoiceValues[pos+1]) end})
repeatCountSpinner.setAdapter(ArrayAdapter(activity, android.R.layout.simple_spinner_dropdown_item, repeatLabels)) repeatCountSpinner.setSelection(repeatIndex) repeatCountSpinner.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{onItemSelected=function(p,v,pos,id) saveAyahRepeatCount(repeatValues[pos+1]) end})
chkAutoNext.setOnCheckedChangeListener(CompoundButton.OnCheckedChangeListener{onCheckedChanged=function(b, isChecked) autoNextMode=isChecked end})
end
function showSocialMedia()
screen = "socialmedia"
local bgColor, textColor = M.getThemeColors()
activity.setContentView(loadlayout{
ScrollView, layout_width=-1, layout_height=-1, fillViewport=true, backgroundColor=bgColor,
{LinearLayout, id="mainLayout", orientation=1, padding="20dp", layout_width=-1, layout_height=-1, gravity="center_horizontal",
{TextView, text="Social Media Support", textSize="24sp", typeface=Typeface.DEFAULT_BOLD, layout_marginBottom="20dp", layout_marginTop="10dp", textColor=appColorStr},
{TextView, text="Community: WhatsApp Group", textSize="12sp", textColor="#777777", layout_width=-1, layout_marginTop="10dp"},
{Button, text="Join WhatsApp Community", textSize="14sp", layout_width=-1, layout_marginBottom="10dp", backgroundColor="#25D366", textColor=-1, onClick=function() M.openLinkAndClose("https://chat.whatsapp.com/ItdQOG8lw5E6DKsxx9iNSd") end},
{TextView, text="Channel: Bridge Tech Welfare", textSize="12sp", textColor="#777777", layout_width=-1, layout_marginTop="10dp"},
{Button, text="Follow WhatsApp Channel", textSize="14sp", layout_width=-1, layout_marginBottom="10dp", backgroundColor="#128C7E", textColor=-1, onClick=function() M.openLinkAndClose("https://whatsapp.com/channel/0029VbCJfWSAojYuaMuB9E1t") end},
{TextView, text="Channel: Bridge Tech Welfare (Telegram)", textSize="12sp", textColor="#777777", layout_width=-1, layout_marginTop="10dp"},
{Button, text="Join Telegram Channel", textSize="14sp", layout_width=-1, layout_marginBottom="10dp", backgroundColor="#0088CC", textColor=-1, onClick=function() M.openLinkAndClose("https://t.me/+NF0bOu66afYxYWM0") end},
{TextView, text="YouTube Channel: Instructor of BTW", textSize="12sp", textColor="#777777", layout_width=-1, layout_marginTop="10dp"},
{Button, text="Subscribe YouTube Channel", textSize="14sp", layout_width=-1, layout_marginBottom="10dp", backgroundColor="#FF0000", textColor=-1, onClick=function() M.openLinkAndClose("https://youtube.com/@instructor-of-btw?si=nXc_isZVvMV8OQoc") end},
{TextView, text="YouTube Channel: Technology Information", textSize="12sp", textColor="#777777", layout_width=-1, layout_marginTop="10dp"},
{Button, text="Subscribe YouTube Channel", textSize="14sp", layout_width=-1, layout_marginBottom="30dp", backgroundColor="#FF0000", textColor=-1, onClick=function() M.openLinkAndClose("https://www.youtube.com/@Technologyinformation-y4g") end},
{Button, text=tr("Back"), layout_width=-1, backgroundColor=appColorStr, textColor=-1, onClick=function() safeRun("showSettings", showSettings) end}
}
})
M.applyWallpaper(mainLayout, bgColor)
end
function showFeedback()
screen = "feedback"
local bgColor, textColor = M.getThemeColors()
local supportMsg = "Assalam-o-Alaikum! 🌟\n\nWe hope this application helps you in your spiritual journey and becomes a source of Sadqa-e-Jariyah. Your feedback, support, and bug reports are highly valuable to us.\n\nJoin our community using the official links below to stay updated, suggest new features, or connect with the developers.\n\nJazakAllah Khair,\nQuran Majeed Team"
local waMsg = URLEncoder.encode("Assalam-o-Alaikum Numan bhai! MashAllah 'Quran Majeed' app bohot behtareen hai. Allah Pak is koshish ko qabool farmaye aur ise sab ke liye Sadqa-e-Jariyah banaye. Ameen.")
local waNumberUrl = "https://wa.me/923145406759?text=" .. waMsg
activity.setContentView(loadlayout{
ScrollView, layout_width=-1, layout_height=-1, fillViewport=true, backgroundColor=bgColor,
{LinearLayout, id="mainLayout", orientation=1, padding="20dp", layout_width=-1, layout_height=-1, gravity="center_horizontal",
{TextView, text=tr("Feedback & Support"), textSize="24sp", typeface=Typeface.DEFAULT_BOLD, layout_marginBottom="20dp", layout_marginTop="10dp", textColor=appColorStr},
{LinearLayout, orientation=1, layout_width=-1, padding="15dp", layout_marginBottom="20dp", backgroundColor="#1A000000",
{TextView, text=supportMsg, textSize="15sp", gravity="left", textColor=textColor}
},
{Button, text="📱 " .. tr("Direct WhatsApp Feedback"), textSize="14sp", layout_width=-1, layout_marginBottom="20dp", backgroundColor="#25D366", textColor=-1, onClick=function() M.openLinkAndClose(waNumberUrl) end},
{Button, text="💬 Join WhatsApp Group 1", textSize="14sp", layout_width=-1, layout_marginBottom="10dp", backgroundColor="#075E54", textColor=-1, onClick=function() M.openLinkAndClose("https://chat.whatsapp.com/DJY36CzqJdO7uYMsUi1fXp") end},
{Button, text="💬 Join WhatsApp Group 2", textSize="14sp", layout_width=-1, layout_marginBottom="10dp", backgroundColor="#075E54", textColor=-1, onClick=function() M.openLinkAndClose("https://chat.whatsapp.com/KzqqC44433PF2iwsXNd93p") end},
{Button, text="💬 Join WhatsApp Group 3", textSize="14sp", layout_width=-1, layout_marginBottom="10dp", backgroundColor="#075E54", textColor=-1, onClick=function() M.openLinkAndClose("https://chat.whatsapp.com/FsiATGe2BAb2rfNWolL3k4") end},
{Button, text="💬 Join WhatsApp Group 4", textSize="14sp", layout_width=-1, layout_marginBottom="10dp", backgroundColor="#075E54", textColor=-1, onClick=function() M.openLinkAndClose("https://chat.whatsapp.com/JGz8fgOFXth9cTWh3IRF7s?s=cl&p=a&mlu=4") end},
{Button, text="📢 Follow WhatsApp Channel", textSize="14sp", layout_width=-1, layout_marginBottom="10dp", backgroundColor="#128C7E", textColor=-1, onClick=function() M.openLinkAndClose("https://whatsapp.com/channel/0029Vb7I39ILikgHRF0PBV3k") end},
{Button, text="📺 Subscribe YouTube Channel", textSize="14sp", layout_width=-1, layout_marginBottom="30dp", backgroundColor="#FF0000", textColor=-1, onClick=function() M.openLinkAndClose("https://youtube.com/@friendtagresourcesteam?si=mT_M3jqVLcpwlRjN") end},
{Button, text=tr("Back"), layout_width=-1, backgroundColor=appColorStr, textColor=-1, onClick=function() safeRun("showSettings", showSettings) end}
}
})
M.applyWallpaper(mainLayout, bgColor)
end
function showAbout()
screen = "about"
local bgColor, textColor = M.getThemeColors()
local infoText = [[QURAN MAJEED v3.1 - WHAT'S NEW

NAYA (IS VERSION MEIN):
* Books ka bada update: 40 naye mukammal collections (14 Urdu,
  9 English, 9 Arabic tilawatein, 8 naye Naat collections) - sab
  archive.org se file-by-file verify kiye gaye, koi andaza nahi.
* Urdu naye: Tafseer Ahsanul Bayan (247), Tafseer Dr. Mir Aneesuddin
  (219), Fahm-ul-Quran Dr. Farhat Hashmi (108), Khulasa Quran
  para-wise (30), Madinah Arabic Books 1-3 Urdu (82 sabaq), Hazrat
  Umar Farooq 60 Episoad, Daur-e-Quran Course (74), Tafseer-e-Quran
  Qasmi Dora (573), Zikr-e-Khair (26), Seerat Dr. Israr (5), Seerat
  Khalid bin Waleed (2), Best Reminder Bayanat (79).
* English naye: Dr. Israr English Tafseer (113), Riyad-us-Saliheen
  English (372), Quran Tafsir Muhsin Khan (114), Quran + English
  Translation Mishary (115), Sahih Muslim English (56), 40 Hadith
  Masjid (42), Short Reminders (77), Seerah Makkah Period (16),
  Usul-ul-Hadith (10).
* Arabic naye tilawatein (114 Surah each): Husary, Ghamdi, Minshawi,
  Ajmy, Alafasy, Muaiqly, Abdul Basit, Hosyn Amer, Belaalih (Warsh).
* Naat category 6 se 14 collections: Famous Naat Khawans (638),
  Hafiz Tahir Qadri (141), Anas Yunus (45), Pashto albums (31),
  Hamad Bari (12), Aey Mere Moula (3). Kul 1492 naatein.
* Naats aur Bayanat screens par ab proper English labels hain,
  version home screen par 3.1.
* Quran ke surah-wise aur para-wise tarjume ab Books se nikal kar Quran
  player ke Translations mein hain. Ab 25 qari/tarjuma modes hain:
  Urdu 15 (Waheed Zafar, Shakir Qasmi, Sudais-Shuraim, Abdul Basit,
  Maher Al Muaiqly, Abdullah Momin, Saud Al Shuraim, Minshawi,
  Hani Al Rifai, Ajmi, Basfar, Taqi Usmani Aasan Tarjuma, FMJ,
  sirf tarjuma, Irfan-ul-Quran, Kanzul Iman Attari), English 2,
  Hindi 2 (128k + 64k), Punjabi, Arabic, Chinese 2, para-wise 2.
  jo tarjuma Books mein dup tha, wahin remove kiya (14 entries).
* Naats category (More menu mein): 14 collections, 1492 naatein -
  Owais Raza Qadri (257), Islamic Academy (249), Mufti Akhtar Raza
  Khan (67), Junaid Jamshed (10), Meray Khawja Pia Tahir (27),
  Asmatullah Jarar (12). Har naat mukammal hai.
* Bayanat category (More menu mein): 12 collections, 1468 bayanat -
  Bayan-ul-Quran (Dr. Israr Ahmed, 117), Tafheem-ul-Quran (Maududi,
  115), Tafsir Ibne Kaseer (115), Tafseer Qasmi (39), Seerat Bayan
  Series (30), Faizan-e-Ala Hazrat (183), Duroos-ul-Balagha (91),
  Mufti Arshad Kowloon Masjid (61), Ala Hazrat.net (29), Jadu ki
  Haqeeqat (36).
* Islam Books ab 48 mukammal kitaabein (Urdu 28, English 10, Arabic 10)
  kitaabein (Qisas-ul-Ambiya, Seerat, Ar Raheeq, Bukhari, Riyad-us-
  Saliheen, Sharh Tawheed, Hisnul Muslim, Bachon ki Kahaniyan,
  Jab Zindagi, Sahih Muslim Arabic, Guide for New Muslim waghera).

PEHLE SE THEEK (PURANE FIX):
* Hijri tareekh offline sahi (16 Rabi-us-Sani 1448), hang khatam,
  6 Kalme/Namaz/Janaza alag audio, error report Copy/Share ke sath,
  books player sirf khuli kitaab ka audio bajata hai, advanced search
  (Surah/Dua/Kalma/Kitaab - Urdu aur Roman).

HAR AUDIO: play, pause, seek, speed, download aur offline. Download
sirf mp3, phone ke Downloads/Islam_Books folder mein.]]
activity.setContentView(loadlayout{
ScrollView, id="mainLayout", layout_width=-1, layout_height=-1, fillViewport=true, backgroundColor=bgColor,
{LinearLayout, orientation=1, padding="20dp", layout_width=-1, layout_height=-1, gravity="center_horizontal",
{TextView, text=tr("About App"), textSize="24sp", typeface=Typeface.DEFAULT_BOLD, layout_marginBottom="20dp", layout_marginTop="10dp", textColor=appColorStr},
{TextView, text=infoText, textSize="14sp", gravity="left", layout_marginBottom="40dp", textColor=textColor},
{Button, text=tr("Back"), layout_width=-1, backgroundColor=appColorStr, textColor=-1, onClick=function() safeRun("showSettings", showSettings) end}
}
})
M.applyWallpaper(mainLayout, bgColor)
end
function playNextSurah() if currentIndex < #surahNames then currentIndex = currentIndex + 1 showPlayer(currentIndex) end end
function playPrevSurah() if currentIndex > 1 then currentIndex = currentIndex - 1 showPlayer(currentIndex) end end
function V25.buildErrorReport(title, errText)
local function g(f) local ok, v = pcall(f) if ok and v ~= nil then return tostring(v) end return "?" end
local lines = {}
table.insert(lines, "Quran Majeed v3.1 - ERROR REPORT")
table.insert(lines, "Time     : " .. g(function() return os.date("%Y-%m-%d %H:%M:%S") end))
table.insert(lines, "Screen   : " .. tostring(screen))
table.insert(lines, "Where    : " .. tostring(title or "Unknown"))
table.insert(lines, "Android  : " .. g(function() return Build.VERSION.RELEASE end) .. " (SDK " .. g(function() return Build.VERSION.SDK_INT end) .. ")")
table.insert(lines, "Device   : " .. g(function() return Build.MANUFACTURER end) .. " " .. g(function() return Build.MODEL end))
table.insert(lines, "Location : " .. tostring(savedCity) .. ", " .. tostring(savedCountry))
table.insert(lines, "------------------------------------------")
table.insert(lines, tostring(errText))
return table.concat(lines, "\n")
end
function V25.copyTextToClipboard(txt)
local ok = pcall(function()
activity.getSystemService(Context.CLIPBOARD_SERVICE).setPrimaryClip(ClipData.newPlainText("Quran Majeed", tostring(txt)))
end)
if ok then
pcall(function() Toast.makeText(activity, "Copy ho gaya! Ab paste kar ke bhejein.", 0).show() end)
else
pcall(function() Toast.makeText(activity, "Copy nahi ho saka - text ko long-press kar ke select karein.", 1).show() end)
end
end
function showErrorDialog(title, errText)
local ok = pcall(function()
local msg = V25.buildErrorReport(title, errText)
local tv = TextView(activity)
tv.setText(msg)
pcall(function() tv.setTextIsSelectable(true) end)
pcall(function() tv.setPadding(24, 18, 24, 18) end)
pcall(function() tv.setTextSize(11) end)
AlertDialog.Builder(activity)
.setTitle("⚠ " .. tostring(title or "Error") .. " - Copy / Share karein")
.setView(tv)
.setPositiveButton("Copy", {onClick=function() V25.copyTextToClipboard(msg) end})
.setNeutralButton("Share", {onClick=function()
pcall(function()
local shareIntent = Intent(Intent.ACTION_SEND)
shareIntent.setType("text/plain")
shareIntent.putExtra(Intent.EXTRA_SUBJECT, "Quran Majeed v3.1 error report")
shareIntent.putExtra(Intent.EXTRA_TEXT, msg)
activity.startActivity(Intent.createChooser(shareIntent, "Error bhejein (WhatsApp / Email)"))
end)
end})
.setNegativeButton("Cancel", nil)
.show()
end)
if not ok then
pcall(function() Toast.makeText(activity, "Error: " .. tostring(errText), 1).show() end)
end
end
function safeRun(label, fn, ...)
if type(fn) ~= "function" then return false end
local unpackFn = table.unpack or unpack
local args = {...}
local ok, err = xpcall(function() return fn(unpackFn(args)) end, function(e)
local tb = tostring(e)
pcall(function() if debug and debug.traceback then tb = debug.traceback(tostring(e), 2) end end)
return tb
end)
if not ok then showErrorDialog(label or "Error", err) end
return ok, err
end
function downloadSurah(url, fileName, title)
local ok, err = pcall(function()
local req = DownloadManager.Request(Uri.parse(url))
req.setTitle(title)
req.setDescription("Downloading...")
req.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
req.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, "Quran_Files/" .. fileName)
activity.getSystemService(Context.DOWNLOAD_SERVICE).enqueue(req)
end)
if ok then
Toast.makeText(activity, "Download shuru ho gaya... khatam hote hi is Surah screen par wapis aakar offline play karein.", 1).show()
else
showErrorDialog("Download Error", err)
end
end
function confirmDelete(filePath, onSuccess) AlertDialog.Builder(activity).setTitle("Delete Confirmation").setMessage("Delete this offline file?").setPositiveButton("Yes", {onClick=function() local f=File(filePath) if f.exists() then f.delete() end Toast.makeText(activity,"Deleted",0).show() if onSuccess then onSuccess() end end}).setNegativeButton("No", nil).show() end
local rukuCache = {}
local ayahTextCache = {}
M.getSurahMetaCachePath = function(surahIdx) return activity.getCacheDir().getAbsolutePath() .. "/meta_surah" .. surahIdx .. ".json" end
M.saveSurahMetaToDisk = function(surahIdx, list, texts)
pcall(function()
local f = io.open(M.getSurahMetaCachePath(surahIdx), "w")
if f then
for _, r in ipairs(list) do
for a = r.startAyah, r.endAyah do
f:write(tostring(a) .. "|" .. tostring(r.globalRuku) .. "|" .. tostring(texts[a] or "") .. "\n")
end
end
f:close()
end
end)
end
M.loadSurahMetaFromDisk = function(surahIdx)
local path = M.getSurahMetaCachePath(surahIdx)
if not File(path).exists() then return nil, nil end
local ok, list, texts = pcall(function()
local f = io.open(path, "r")
if not f then return nil, nil end
local list2 = {}
local texts2 = {}
local curRuku = nil
for lineStr in f:lines() do
local aStr, rStr, txt = lineStr:match("^(%d+)|(%d+)|(.*)$")
if aStr then
local a = tonumber(aStr)
local rukuNum = tonumber(rStr)
texts2[a] = txt
if not curRuku or curRuku.globalRuku ~= rukuNum then
curRuku = {globalRuku=rukuNum, startAyah=a, endAyah=a}
table.insert(list2, curRuku)
else
curRuku.endAyah = a
end
end
end
f:close()
return list2, texts2
end)
if ok then return list, texts end
return nil, nil
end
M.fetchSurahMeta = function(surahIdx, callback)
if rukuCache[surahIdx] and ayahTextCache[surahIdx] then callback(rukuCache[surahIdx], ayahTextCache[surahIdx]) return end
local diskList, diskTexts = M.loadSurahMetaFromDisk(surahIdx)
if diskList and diskTexts and next(diskTexts) then
rukuCache[surahIdx] = diskList
ayahTextCache[surahIdx] = diskTexts
callback(diskList, diskTexts)
return
end
Thread(Runnable{run=function()
local ok, result, texts = pcall(function()
local conn = URL("https://api.alquran.cloud/v1/surah/" .. surahIdx .. "/quran-uthmani").openConnection()
conn.setConnectTimeout(10000) conn.setReadTimeout(15000)
local reader = BufferedReader(InputStreamReader(conn.getInputStream()))
local res = "" local line = reader.readLine()
while line do res = res..line line = reader.readLine() end
reader.close()
local JSONObject = luajava.bindClass("org.json.JSONObject")
local root = JSONObject(res)
local data = root.getJSONObject("data")
local ayahs = data.getJSONArray("ayahs")
local list = {}
local ayahTexts = {}
local curRuku = nil
for i=0, ayahs.length()-1 do
local a = ayahs.getJSONObject(i)
local ayahNum = a.getInt("numberInSurah")
local rukuNum = a.getInt("ruku")
ayahTexts[ayahNum] = tostring(a.getString("text"))
if not curRuku or curRuku.globalRuku ~= rukuNum then
curRuku = {globalRuku=rukuNum, startAyah=ayahNum, endAyah=ayahNum}
table.insert(list, curRuku)
else
curRuku.endAyah = ayahNum
end
end
return list, ayahTexts
end)
handler.post(Runnable{run=function()
if ok and result and #result > 0 then
rukuCache[surahIdx] = result
ayahTextCache[surahIdx] = texts or {}
M.saveSurahMetaToDisk(surahIdx, result, texts or {})
callback(result, ayahTextCache[surahIdx])
else
callback(nil, nil)
end
end})
end}).start()
end
local WBW = { player=nil, timingIndex=nil, words=nil, timings=nil, wordIdx=1, surahIdx=1, ayahNum=1, autoAdv=false, stopHandle=nil, pendingWordDuration=200, onWordPlaybackDone=nil, timingUrl="https://github.com/cpfair/quran-align/releases/download/release-2016-11-24/Alafasy_128kbps.json", timingCachePath=ayahAudioDir .. "wbw_timing_alafasy.json", timingLoadError=nil, }
function wbwStopAudio()
WBW.onWordPlaybackDone = nil
if WBW.stopHandle then pcall(function() handler.removeCallbacks(WBW.stopHandle) end) WBW.stopHandle = nil end
if WBW.player then
local oldP = WBW.player
WBW.player = nil
Thread(Runnable{run=function()
pcall(function() if oldP.isPlaying() then oldP.stop() end end)
pcall(function() oldP.release() end)
end}).start()
end
end
function httpGetFollowRedirects(urlStr, maxRedirects)
local curUrl = urlStr
for i = 1, (maxRedirects or 5) do
local conn = URL(curUrl).openConnection()
conn.setConnectTimeout(20000) conn.setReadTimeout(60000)
conn.setInstanceFollowRedirects(false)
pcall(function() conn.setRequestProperty("User-Agent", "Mozilla/5.0") end)
local rc = conn.getResponseCode()
if rc >= 300 and rc < 400 then
local loc = conn.getHeaderField("Location")
pcall(function() conn.disconnect() end)
if not loc or loc == "" then error("Redirect mila lekin Location header khaali tha") end
curUrl = loc
else
if rc ~= 200 then error("HTTP " .. rc) end
local reader = BufferedReader(InputStreamReader(conn.getInputStream()))
local res = "" local line = reader.readLine()
while line do res = res..line line = reader.readLine() end
reader.close()
return res
end
end
error("Bohot zyada redirects (5+)")
end
function wbwLoadTimingIndex(onDone)
if WBW.timingIndex then onDone(true) return end
Thread(Runnable{run=function()
local ok, raw = pcall(function()
if File(WBW.timingCachePath).exists() and File(WBW.timingCachePath).length() > 1000 then
local f = io.open(WBW.timingCachePath, "r")
local c = f:read("*a")
f:close()
return c
end
local res = httpGetFollowRedirects(WBW.timingUrl, 5)
pcall(function()
local fo = io.open(WBW.timingCachePath, "w")
fo:write(res)
fo:close()
end)
return res
end)
if not ok or not raw then
WBW.timingLoadError = "Timing file download nahi hui: " .. tostring(raw)
handler.post(Runnable{run=function() onDone(false) end})
return
end
local idx = {}
local pok, perr = pcall(function()
local JSONArray = luajava.bindClass("org.json.JSONArray")
local arr = JSONArray(raw)
for i=0, arr.length()-1 do
local o = arr.getJSONObject(i)
local s = o.getInt("surah")
local a = o.getInt("ayah")
local segsJson = o.getJSONArray("segments")
local segs = {}
for j=0, segsJson.length()-1 do
local seg = segsJson.getJSONArray(j)
segs[#segs+1] = {seg.getInt(0), seg.getInt(1), seg.getInt(2), seg.getInt(3)}
end
idx[string.format("%d_%d", s, a)] = segs
end
end)
if not pok then WBW.timingLoadError = "Timing file parse nahi hui: " .. tostring(perr) end
handler.post(Runnable{run=function()
if pok then WBW.timingIndex = idx end
onDone(pok)
end})
end}).start()
end
function wbwLoadAyah(surahIdx, ayahNum, onReady)
wbwLoadTimingIndex(function(timingOk)
M.fetchSurahMeta(surahIdx, function(list, texts)
if not texts or not texts[ayahNum] then
onReady(false, "Ayat ka text load nahi hua. Internet check karein.")
return
end
local words = {}
for w in tostring(texts[ayahNum]):gmatch("%S+") do words[#words+1] = w end
WBW.words = words
local segs = (WBW.timingIndex and WBW.timingIndex[string.format("%d_%d", surahIdx, ayahNum)]) or {}
local tim = {}
for _, seg in ipairs(segs) do
local ws, we, st, en = seg[1], seg[2], seg[3], seg[4]
for i = ws, we - 1 do tim[i+1] = {st, en} end
end
local hasExactTiming = next(tim) ~= nil
WBW.timings = tim
WBW.wordIdx = 1
local localPath = M.getAyahAudioLocal(surahIdx, ayahNum)
local playUrl = File(localPath).exists() and localPath or M.buildAyahUrl(surahIdx, ayahNum)
wbwStopAudio()
local ok = pcall(function()
WBW.player = MediaPlayer()
pcall(function() WBW.player.setAudioStreamType(AudioManager.STREAM_MUSIC) end)
pcall(function() WBW.player.setWakeMode(activity, PowerManager.PARTIAL_WAKE_LOCK) end)
WBW.player.setDataSource(playUrl)
WBW.player.setOnPreparedListener(MediaPlayer.OnPreparedListener{onPrepared=function(p)
if not hasExactTiming then
local dur = 0
pcall(function() dur = p.getDuration() end)
if dur and dur > 0 and #words > 0 then
local est = {}
for i = 1, #words do
est[i] = {math.floor((i-1) * dur / #words), math.floor(i * dur / #words)}
end
WBW.timings = est
end
end
onReady(true, nil, hasExactTiming)
end})
WBW.player.setOnSeekCompleteListener(MediaPlayer.OnSeekCompleteListener{onSeekComplete=function(p)
pcall(function() p.start() end)
WBW.stopHandle = Runnable{run=function()
pcall(function() if WBW.player and WBW.player.isPlaying() then WBW.player.pause() end end)
WBW.stopHandle = nil
if screen == "wbwmode" and WBW.onWordPlaybackDone then WBW.onWordPlaybackDone() end
end}
handler.postDelayed(WBW.stopHandle, WBW.pendingWordDuration)
end})
WBW.player.setOnErrorListener(MediaPlayer.OnErrorListener{onError=function(p,w,e)
if playUrl ~= localPath then
Toast.makeText(activity, "Online stream nahi hui - internet check kar ke dobara try karein.", 1).show()
onReady(false, "Ayat ki audio online load nahi hui (auto-download ab band hai - hang fix).")
else
onReady(false, "Ayat ki audio load nahi hui (downloaded file kharab hai).")
end
return true
end})
WBW.player.prepareAsync()
end)
if not ok then onReady(false, "Audio player error.") end
end)
end)
end
function showWbwStartDialog(surahIdx)
local mx = surahAyahCounts[surahIdx] or 1
local defaultAyah = lastAyahProgress[surahIdx] or 1
local inp = EditText(activity)
inp.setHint("Ayat number (1-" .. mx .. ")")
inp.setText(tostring(defaultAyah))
AlertDialog.Builder(activity).setTitle("Word-by-Word: " .. surahNames[surahIdx]).setView(inp).setPositiveButton("Shuru Karein", {onClick=function()
local av = tonumber(inp.getText().toString()) or 1
if av < 1 then av = 1 end
if av > mx then av = mx end
showWordByWordMode(surahIdx, av)
end}).setNegativeButton("Cancel", nil).show()
end
function showWordByWordMode(surahIdx, startAyah)
screen = "wbwmode"
WBW.surahIdx = surahIdx
WBW.ayahNum = startAyah or 1
wbwStopAudio()
local bgColor, textColor = M.getThemeColors()
activity.setContentView(loadlayout{
LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor,
{LinearLayout, orientation=0, padding="10dp", backgroundColor="#00695C", layout_width=-1, gravity="center_vertical",
{Button, text=tr("Back"), contentDescription="Back to Surah player", onClick=function() wbwStopAudio() showPlayer(WBW.surahIdx) end},
{TextView, id="wbwHeaderTxt", text=surahNames[surahIdx] .. " - Ayat " .. WBW.ayahNum .. "/" .. (surahAyahCounts[surahIdx] or "?"), textSize="14sp", typeface=Typeface.DEFAULT_BOLD, layout_marginLeft="10dp", textColor=-1}
},
{TextView, id="wbwStatusTxt", text="Loading...", textSize="12sp", textColor="#777777", padding="6dp", gravity="center"},
{TextView, id="wbwWordTxt", text="", textSize="46sp", typeface=Typeface.DEFAULT_BOLD, textColor=appColorStr, gravity="center", padding="10dp", layout_width=-1, layout_height=0, layout_weight=3, contentDescription="Current word"},
{TextView, id="wbwCountTxt", text="", textSize="13sp", textColor=textColor, gravity="center"},
{LinearLayout, orientation=0, gravity="center", layout_width=-1, layout_marginTop="10dp",
{Button, id="wbwPrevWordBtn", text="Prev Lafz", textSize="13sp", layout_weight=1, layout_margin="2dp", contentDescription="Previous word"},
{Button, id="wbwPlayWordBtn", text="Sunein", textSize="14sp", typeface=Typeface.DEFAULT_BOLD, layout_weight=1.2, layout_margin="2dp", contentDescription="Play this word"},
{Button, id="wbwNextWordBtn", text="Next Lafz", textSize="13sp", layout_weight=1, layout_margin="2dp", contentDescription="Next word"}
},
{LinearLayout, orientation=0, gravity="center", layout_width=-1, layout_marginTop="8dp",
{Button, id="wbwAutoBtn", text="Auto: OFF", textSize="12sp", layout_weight=1, layout_margin="2dp", contentDescription="Toggle auto advance to next word"},
{Button, id="wbwPrevAyahBtn", text="Pichli Ayat", textSize="12sp", layout_weight=1, layout_margin="2dp", contentDescription="Previous Ayat"},
{Button, id="wbwNextAyahBtn", text="Agli Ayat", textSize="12sp", layout_weight=1, layout_margin="2dp", contentDescription="Next Ayat"}
}
})
M.applyWallpaper(mainLayout, bgColor)
local function renderWord()
if WBW.words and WBW.words[WBW.wordIdx] then
pcall(function()
wbwWordTxt.setText(WBW.words[WBW.wordIdx])
wbwCountTxt.setText("Lafz " .. WBW.wordIdx .. " / " .. #WBW.words)
end)
end
end
local playCurrentWord
playCurrentWord = function()
if WBW.stopHandle then pcall(function() handler.removeCallbacks(WBW.stopHandle) end) WBW.stopHandle = nil end
if not WBW.player then
Toast.makeText(activity, "Audio abhi taiyar nahi hui, thoda intezar karein.", 0).show()
return
end
local t = WBW.timings and WBW.timings[WBW.wordIdx]
if not t then
local dur = 0
pcall(function() dur = WBW.player.getDuration() end)
if dur and dur > 0 and WBW.words and #WBW.words > 0 then
local st = math.floor((WBW.wordIdx - 1) * dur / #WBW.words)
local en = math.floor(WBW.wordIdx * dur / #WBW.words)
t = {st, en}
WBW.timings = WBW.timings or {}
WBW.timings[WBW.wordIdx] = t
end
end
if not t then
Toast.makeText(activity, "Is lafz ke liye audio timing nahi mili (audio duration abhi maloom nahi ho saki).", 0).show()
return
end
local st, en = t[1], t[2]
WBW.pendingWordDuration = math.max(en - st, 200)
pcall(function() WBW.player.seekTo(st) end)
end
WBW.onWordPlaybackDone = function()
if WBW.autoAdv and WBW.words and WBW.wordIdx < #WBW.words then
WBW.wordIdx = WBW.wordIdx + 1
renderWord()
playCurrentWord()
end
end
local function loadAndRender()
pcall(function()
wbwStatusTxt.setText("Loading...")
wbwWordTxt.setText("")
wbwHeaderTxt.setText(surahNames[WBW.surahIdx] .. " - Ayat " .. WBW.ayahNum .. "/" .. (surahAyahCounts[WBW.surahIdx] or "?"))
end)
wbwLoadAyah(WBW.surahIdx, WBW.ayahNum, function(ok, err, exact)
if screen ~= "wbwmode" then return end
if ok then
pcall(function()
if exact then
wbwStatusTxt.setText("Reciter: Mishary Alafasy - lafz par Sunein dabayein")
else
wbwStatusTxt.setText("Reciter: Mishary Alafasy - andazan (approximate) taqseem, is ayat ke liye exact lafz-timing maujood nahi")
end
M.saveLastAyahProgress(WBW.surahIdx, WBW.ayahNum)
end)
renderWord()
else
pcall(function() wbwStatusTxt.setText(err or "Load nahi hua.") end)
end
end)
end
wbwPlayWordBtn.onClick = function() playCurrentWord() end
wbwPrevWordBtn.onClick = function() if WBW.words and WBW.wordIdx > 1 then WBW.wordIdx = WBW.wordIdx - 1 renderWord() end end
wbwNextWordBtn.onClick = function() if WBW.words and WBW.wordIdx < #WBW.words then WBW.wordIdx = WBW.wordIdx + 1 renderWord() end end
wbwAutoBtn.onClick = function()
WBW.autoAdv = not WBW.autoAdv
wbwAutoBtn.setText(WBW.autoAdv and "Auto: ON" or "Auto: OFF")
pcall(function() wbwAutoBtn.setBackgroundColor(Color.parseColor(WBW.autoAdv and "#1565C0" or "#607D8B")) end)
end
wbwPrevAyahBtn.onClick = function()
if WBW.ayahNum > 1 then WBW.ayahNum = WBW.ayahNum - 1
elseif WBW.surahIdx > 1 then WBW.surahIdx = WBW.surahIdx - 1 WBW.ayahNum = surahAyahCounts[WBW.surahIdx] or 1
else return end
wbwStopAudio()
loadAndRender()
end
wbwNextAyahBtn.onClick = function()
local mx = surahAyahCounts[WBW.surahIdx] or 1
if WBW.ayahNum < mx then WBW.ayahNum = WBW.ayahNum + 1
elseif WBW.surahIdx < 114 then WBW.surahIdx = WBW.surahIdx + 1 WBW.ayahNum = 1
else return end
wbwStopAudio()
loadAndRender()
end
loadAndRender()
end
function showAyahByAyah(surahIdx, autoPlayAyat)
screen = "ayahmode"
local bgColor, textColor = M.getThemeColors()
local totalAyahs = surahAyahCounts[surahIdx] or 0
local alreadyDownloaded = 0
for a=1, totalAyahs do
if File(M.getAyahAudioLocal(surahIdx, a)).exists() then alreadyDownloaded = alreadyDownloaded + 1 end
end
local function buildLabels(texts)
local labels = {}
for a=1, totalAyahs do
if texts and texts[a] then
table.insert(labels, "Ayat " .. a .. "  -  " .. texts[a])
else
table.insert(labels, "Ayat " .. a)
end
end
return labels
end
activity.setContentView(loadlayout{
LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor,
{LinearLayout, orientation=0, padding="10dp", backgroundColor="#00695C", layout_width=-1, gravity="center_vertical",
{Button, text=tr("Back"), contentDescription="Back to Surah player", onClick=function() showPlayer(surahIdx) end},
{TextView, text=surahNames[surahIdx] .. " - Ayat-ba-Ayat", textSize="15sp", typeface=Typeface.DEFAULT_BOLD, layout_marginLeft="10dp", textColor=-1}
},
{TextView, id="txtAyahStatus", text="Reciter: Mishary Alafasy (fixed reciter for this mode). Tap an Ayat to play it, long-press for Copy/Share.", textSize="11sp", textColor="#777777", padding="8dp"},
(lastAyahProgress[surahIdx] and {Button, id="btnResumeAyah", text="Resume from Ayat " .. lastAyahProgress[surahIdx], textSize="13sp", backgroundColor="#FF8F00", textColor=-1, layout_margin="8dp"}) or {LinearLayout, orientation=0, layout_width=-1, layout_height=0},
{LinearLayout, orientation=0, gravity="center_vertical", layout_width=-1, padding="8dp",
{TextView, text="Ayat Repeat:", textSize="13sp", textColor=textColor, layout_marginRight="8dp"},
{Spinner, id="ayahRepeatSpinner", layout_width=0, layout_weight=1}
},
{TextView, id="txtDownloadProgress", text="Downloaded for offline: " .. alreadyDownloaded .. " / " .. totalAyahs, textSize="12sp", typeface=Typeface.DEFAULT_BOLD, textColor=appColorStr, padding="8dp"},
{Button, id="btnDownloadAllAyahs", text="Download All Ayahs for Offline", textSize="13sp", backgroundColor="#1976D2", textColor=-1, layout_margin="8dp"},
{ListView, id="ayahList", layout_width=-1, layout_height=0, layout_weight=1}
})
M.applyWallpaper(mainLayout, bgColor)
do
local repLabels = {"1x (No Repeat)", "2x", "3x", "5x", "10x"}
local repValues = {1, 2, 3, 5, 10}
local repIndex = 0
for i,v in ipairs(repValues) do if v == PS.ayahRepeat then repIndex = i - 1 break end end
ayahRepeatSpinner.setAdapter(ArrayAdapter(activity, android.R.layout.simple_spinner_dropdown_item, repLabels))
ayahRepeatSpinner.setSelection(repIndex)
ayahRepeatSpinner.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{onItemSelected=function(p,v,pos,id)
saveAyahRepeatCount(repValues[pos+1])
end})
end
local function playAyahRepeated(n, remainingRepeats)
if n < 1 or n > totalAyahs then return end
if remainingRepeats < 1 then return end
local repeatTotal = PS.ayahRepeat
local repeatNow = repeatTotal - remainingRepeats + 1
local statusSuffix = (repeatTotal > 1) and (" (repeat " .. repeatNow .. "/" .. repeatTotal .. ")") or ""
pcall(function() txtAyahStatus.setText("Playing Ayat " .. n .. " of " .. totalAyahs .. statusSuffix) end)
M.saveLastAyahProgress(surahIdx, n)
local function afterOneRound()
if remainingRepeats > 1 then playAyahRepeated(n, remainingRepeats - 1) end
end
M.playReliable(M.buildAyahUrl(surahIdx, n), M.getAyahAudioLocal(surahIdx, n), surahNames[surahIdx] .. " Ayat " .. n, nil, function()
if translationMode == "Urdu" then
local uUrl, uPath = M.currentUrduAyahPair(surahIdx, n)
M.playReliable(uUrl, uPath, surahNames[surahIdx] .. " Ayat " .. n .. " (Urdu)", nil, afterOneRound)
elseif translationMode == "English" then
M.playReliable(M.buildEnglishAyahUrl(surahIdx, n), M.getEnglishAyahAudioLocal(surahIdx, n), surahNames[surahIdx] .. " Ayat " .. n .. " (English)", nil, afterOneRound)
elseif translationMode == "Farsi" then
M.playReliable(M.buildFarsiAyahUrl(surahIdx, n), M.getFarsiAyahAudioLocal(surahIdx, n), surahNames[surahIdx] .. " Ayat " .. n .. " (Farsi)", nil, afterOneRound)
else
afterOneRound()
end
end)
end
local function playAyah(n) playAyahRepeated(n, PS.ayahRepeat) end
if lastAyahProgress[surahIdx] and btnResumeAyah then
btnResumeAyah.onClick = function() playAyah(lastAyahProgress[surahIdx]) end
end
ayahList.setAdapter(ArrayAdapter(activity, android.R.layout.simple_list_item_1, buildLabels(nil)))
ayahList.onItemClick = function(l, v, p, i) playAyah(i + 1) end
ayahList.onItemLongClick = function(l, v, p, i)
local n = i + 1
local ayahText = ayahTextCache[surahIdx] and ayahTextCache[surahIdx][n]
AlertDialog.Builder(activity).setTitle(surahNames[surahIdx] .. " - Ayat " .. n).setItems({"▶️ Play", "📋 Copy Text", "📤 Share Text", "❌ Cancel"}, {onClick=function(d, w)
if w == 0 then
playAyah(n)
elseif w == 1 then
if ayahText then
pcall(function() activity.getSystemService(Context.CLIPBOARD_SERVICE).setPrimaryClip(ClipData.newPlainText("Ayat", ayahText)) end)
Toast.makeText(activity, "Ayat text copied!", 0).show()
else
Toast.makeText(activity, "Ayat text abhi load nahi hui, thoda intezar karein.", 0).show()
end
elseif w == 2 then
if ayahText then
pcall(function()
local shareText = ayahText .. "\n\n(" .. surahNames[surahIdx] .. " " .. n .. ")"
local shareIntent = Intent(Intent.ACTION_SEND)
shareIntent.setType("text/plain")
shareIntent.putExtra(Intent.EXTRA_TEXT, shareText)
activity.startActivity(Intent.createChooser(shareIntent, "Share Ayat"))
end)
else
Toast.makeText(activity, "Ayat text abhi load nahi hui, thoda intezar karein.", 0).show()
end
end
end}).show()
return true
end
if autoPlayAyat then playAyah(autoPlayAyat) end
M.fetchSurahMeta(surahIdx, function(list, texts)
if screen == "ayahmode" and texts then
pcall(function() ayahList.setAdapter(ArrayAdapter(activity, android.R.layout.simple_list_item_1, buildLabels(texts))) end)
end
end)
btnDownloadAllAyahs.onClick = function()
btnDownloadAllAyahs.setEnabled(false)
btnDownloadAllAyahs.setText("Downloading...")
local items = {}
for a=1, totalAyahs do
table.insert(items, {url=M.buildAyahUrl(surahIdx, a), path=M.getAyahAudioLocal(surahIdx, a)})
end
local totalItems = totalAyahs
if translationMode == "Urdu" then
for a=1, totalAyahs do
local uUrl, uPath = M.currentUrduAyahPair(surahIdx, a)
table.insert(items, {url=uUrl, path=uPath})
end
totalItems = totalAyahs * 2
elseif translationMode == "English" then
for a=1, totalAyahs do
table.insert(items, {url=M.buildEnglishAyahUrl(surahIdx, a), path=M.getEnglishAyahAudioLocal(surahIdx, a)})
end
totalItems = totalAyahs * 2
elseif translationMode == "Farsi" then
for a=1, totalAyahs do
table.insert(items, {url=M.buildFarsiAyahUrl(surahIdx, a), path=M.getFarsiAyahAudioLocal(surahIdx, a)})
end
totalItems = totalAyahs * 2
end
M.downloadSequentially(items, 1, 0, function(doneSoFar, idx)
if idx % 3 == 0 or idx == totalItems then
if screen == "ayahmode" then pcall(function() txtDownloadProgress.setText("Downloaded for offline: " .. doneSoFar .. " / " .. totalItems) end) end
end
end, function(done)
if screen == "ayahmode" then
pcall(function()
btnDownloadAllAyahs.setEnabled(true)
btnDownloadAllAyahs.setText("Download All Ayahs for Offline")
if done < totalItems then
Toast.makeText(activity, "Downloaded " .. done .. " / " .. totalItems .. ". Kuch fail hui - error: " .. lastDownloadError, 1).show()
else
Toast.makeText(activity, "Download complete: " .. done .. " / " .. totalItems .. " files saved for offline.", 1).show()
end
end)
end
end)
end
end
function showRukuMode(surahIdx)
screen = "rukumode"
local bgColor, textColor = M.getThemeColors()
activity.setContentView(loadlayout{
LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor,
{LinearLayout, orientation=0, padding="10dp", backgroundColor="#00695C", layout_width=-1, gravity="center_vertical",
{Button, text=tr("Back"), contentDescription="Back to Surah player", onClick=function() showPlayer(surahIdx) end},
{TextView, text=surahNames[surahIdx] .. " - Ruku List", textSize="15sp", typeface=Typeface.DEFAULT_BOLD, layout_marginLeft="10dp", textColor=-1}
},
{TextView, id="txtRukuStatus", text="Loading Ruku data from Al Quran Cloud...", textSize="12sp", textColor="#777777", padding="8dp"},
(lastRukuProgress[surahIdx] and {Button, id="btnResumeRuku", text="Resume Ruku " .. lastRukuProgress[surahIdx], textSize="13sp", backgroundColor="#FF8F00", textColor=-1, layout_margin="8dp"}) or {LinearLayout, orientation=0, layout_width=-1, layout_height=0},
{ListView, id="rukuList", layout_width=-1, layout_height=0, layout_weight=1}
})
M.applyWallpaper(mainLayout, bgColor)
if lastRukuProgress[surahIdx] and btnResumeRuku then
btnResumeRuku.onClick = function() showRukuPlayer(surahIdx, lastRukuProgress[surahIdx]) end
end
M.fetchSurahMeta(surahIdx, function(list, texts)
if screen ~= "rukumode" then return end
if not list then
pcall(function() txtRukuStatus.setText("Ruku data load nahi ho saki - internet check karein.") end)
return
end
pcall(function() txtRukuStatus.setText("Reciter: Mishary Alafasy. Tap a Ruku to play it (Ayat " .. list[1].startAyah .. " se shuru).") end)
local labels = {}
for i, r in ipairs(list) do table.insert(labels, "Ruku " .. i .. " (Ayat " .. r.startAyah .. "-" .. r.endAyah .. ")") end
rukuList.setAdapter(ArrayAdapter(activity, android.R.layout.simple_list_item_1, labels))
rukuList.onItemClick = function(l, v, p, i) showRukuPlayer(surahIdx, i + 1) end
end)
end
function showRukuPlayer(surahIdx, rukuIdx)
screen = "rukuplayer"
M.stopPlayer()
local bgColor, textColor = M.getThemeColors()
local list = rukuCache[surahIdx]
if not list or not list[rukuIdx] then showRukuMode(surahIdx) return end
local ruku = list[rukuIdx]
M.saveLastRukuProgress(surahIdx, rukuIdx)
activity.setContentView(loadlayout{
LinearLayout, id="mainLayout", orientation=1, padding="20dp", layout_width=-1, layout_height=-1, gravity="center", backgroundColor=bgColor,
{TextView, text=surahNames[surahIdx], textSize="22sp", typeface=Typeface.DEFAULT_BOLD, layout_marginBottom="5dp", textColor=appColorStr},
{TextView, text="Ruku " .. rukuIdx .. " of " .. #list .. " (Ayat " .. ruku.startAyah .. "-" .. ruku.endAyah .. ")", textSize="16sp", layout_marginBottom="20dp", textColor=textColor},
{TextView, id="txtRukuPlaying", text="Not playing", textSize="13sp", textColor="#777777", layout_marginBottom="20dp"},
{LinearLayout, orientation=0, gravity="center", layout_width=-1,
{Button, text="Prev Ruku", textSize="13sp", layout_weight=1, layout_margin="2dp", contentDescription="Previous Ruku", onClick=function() if rukuIdx > 1 then showRukuPlayer(surahIdx, rukuIdx-1) end end},
{Button, id="btnRukuPlayPause", text="Play Ruku", textSize="14sp", typeface=Typeface.DEFAULT_BOLD, layout_weight=1.5, layout_margin="2dp", contentDescription="Play this Ruku"},
{Button, text="Next Ruku", textSize="13sp", layout_weight=1, layout_margin="2dp", contentDescription="Next Ruku", onClick=function() if rukuIdx < #list then showRukuPlayer(surahIdx, rukuIdx+1) end end}
},
{Button, id="btnDownloadRuku", text="Download This Ruku for Offline", textSize="13sp", backgroundColor="#1976D2", textColor=-1, layout_marginTop="20dp"},
{TextView, id="txtRukuDlProgress", text="", textSize="12sp", textColor=appColorStr, layout_marginTop="8dp"},
{LinearLayout, orientation=0, gravity="center", layout_marginTop="30dp", layout_width=-1,
{Button, text=tr("Back"), layout_weight=1, contentDescription="Back to Ruku list", onClick=function() showRukuMode(surahIdx) end}
}
})
M.applyWallpaper(mainLayout, bgColor)
local isPlayingRuku = false
local currentAyahInRuku = ruku.startAyah
local function playRukuFrom(n)
if n > ruku.endAyah then
isPlayingRuku = false
pcall(function() txtRukuPlaying.setText("Ruku complete.") btnRukuPlayPause.setText("Play Ruku") end)
return
end
isPlayingRuku = true
currentAyahInRuku = n
pcall(function() txtRukuPlaying.setText("Playing Ayat " .. n .. " (Ruku range " .. ruku.startAyah .. "-" .. ruku.endAyah .. ")") btnRukuPlayPause.setText("Pause") end)
M.playReliable(M.buildAyahUrl(surahIdx, n), M.getAyahAudioLocal(surahIdx, n), surahNames[surahIdx] .. " Ayat " .. n, nil, function()
if translationMode == "Urdu" then
local uUrl, uPath = M.currentUrduAyahPair(surahIdx, n)
M.playReliable(uUrl, uPath, surahNames[surahIdx] .. " Ayat " .. n .. " (Urdu)", nil, function()
if screen == "rukuplayer" and isPlayingRuku then playRukuFrom(n + 1) end
end)
elseif translationMode == "English" then
M.playReliable(M.buildEnglishAyahUrl(surahIdx, n), M.getEnglishAyahAudioLocal(surahIdx, n), surahNames[surahIdx] .. " Ayat " .. n .. " (English)", nil, function()
if screen == "rukuplayer" and isPlayingRuku then playRukuFrom(n + 1) end
end)
elseif translationMode == "Farsi" then
M.playReliable(M.buildFarsiAyahUrl(surahIdx, n), M.getFarsiAyahAudioLocal(surahIdx, n), surahNames[surahIdx] .. " Ayat " .. n .. " (Farsi)", nil, function()
if screen == "rukuplayer" and isPlayingRuku then playRukuFrom(n + 1) end
end)
else
if screen == "rukuplayer" and isPlayingRuku then playRukuFrom(n + 1) end
end
end)
end
btnRukuPlayPause.onClick = function()
if duaMp then
pcall(function()
if duaMp.isPlaying() then
duaMp.pause()
isPlayingRuku = false
btnRukuPlayPause.setText("Play Ruku")
txtRukuPlaying.setText("Paused at Ayat " .. currentAyahInRuku)
else
duaMp.start()
isPlayingRuku = true
btnRukuPlayPause.setText("Pause")
txtRukuPlaying.setText("Playing Ayat " .. currentAyahInRuku .. " (Ruku range " .. ruku.startAyah .. "-" .. ruku.endAyah .. ")")
end
end)
else
playRukuFrom(currentAyahInRuku)
end
end
btnDownloadRuku.onClick = function()
btnDownloadRuku.setEnabled(false)
btnDownloadRuku.setText("Downloading...")
local total = ruku.endAyah - ruku.startAyah + 1
local items = {}
for a = ruku.startAyah, ruku.endAyah do
table.insert(items, {url=M.buildAyahUrl(surahIdx, a), path=M.getAyahAudioLocal(surahIdx, a)})
end
if translationMode == "Urdu" then
for a = ruku.startAyah, ruku.endAyah do
local uUrl, uPath = M.currentUrduAyahPair(surahIdx, a)
table.insert(items, {url=uUrl, path=uPath})
end
total = total * 2
elseif translationMode == "English" then
for a = ruku.startAyah, ruku.endAyah do
table.insert(items, {url=M.buildEnglishAyahUrl(surahIdx, a), path=M.getEnglishAyahAudioLocal(surahIdx, a)})
end
total = total * 2
elseif translationMode == "Farsi" then
for a = ruku.startAyah, ruku.endAyah do
table.insert(items, {url=M.buildFarsiAyahUrl(surahIdx, a), path=M.getFarsiAyahAudioLocal(surahIdx, a)})
end
total = total * 2
end
M.downloadSequentially(items, 1, 0, function(doneSoFar, idx)
if screen == "rukuplayer" then pcall(function() txtRukuDlProgress.setText("Downloaded: " .. doneSoFar .. " / " .. total) end) end
end, function(done)
if screen == "rukuplayer" then
pcall(function() btnDownloadRuku.setEnabled(true) btnDownloadRuku.setText("Download This Ruku for Offline") end)
Toast.makeText(activity, "Ruku download complete: " .. done .. " / " .. total, 1).show()
end
end)
end
end
function showReadingMode(index)
screen = "reading"
local surahName = surahNames[index]
local bgColor, textColor = M.getThemeColors()
activity.setContentView(loadlayout{
LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor,
{LinearLayout, orientation=0, padding="10dp", backgroundColor=appColorStr, layout_width=-1, gravity="center_vertical",
{Button, text="⬅️", onClick=function() showPlayer(index) end},
{TextView, text=surahName, textSize="18sp", typeface=Typeface.DEFAULT_BOLD, layout_marginLeft="10dp", textColor=-1, layout_weight=1},
{Button, text="-", textSize="20sp", onClick=function() if readingFontSize > 12 then readingFontSize = readingFontSize - 2 prefs.edit().putInt("readingFontSize", readingFontSize).apply() showReadingMode(index) end end},
{Button, text="+", textSize="20sp", layout_marginLeft="5dp", onClick=function() if readingFontSize < 40 then readingFontSize = readingFontSize + 2 prefs.edit().putInt("readingFontSize", readingFontSize).apply() showReadingMode(index) end end}
},
{ScrollView, layout_width=-1, layout_height=-1, padding="15dp",
{LinearLayout, orientation=1, layout_width=-1, layout_height=-2,
{TextView, text="بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ", textSize=tostring(readingFontSize+4).."sp", typeface=Typeface.DEFAULT_BOLD, textColor=appColorStr, gravity="center", layout_marginBottom="20dp", layout_marginTop="10dp"},
{TextView, text="(Reading data from JSON will populate here dynamically. Currently showing test UI with adjustable font size. FontSize: "..readingFontSize..")", textSize=tostring(readingFontSize).."sp", textColor=textColor, gravity="center"}
}
}
})
M.applyWallpaper(mainLayout, bgColor)
end
function showPlayer(index)
screen = "player"
PS.externalPlayback=false PS.externalPreparing=false PS.externalPausePending=false
currentIndex = index
local surahName = surahNames[index]
M.saveLastPlayed(currentIndex, currentReciter)
local sID = string.format("%03d", index)
local reciterKey = slug(reciters[currentReciter].name)
local isUrdu = (translationMode == "Urdu")
local isHindi = (translationMode == "Hindi")
local isPunjabi = (translationMode == "Punjabi")
local isEnglish = (translationMode == "English")
local isSindhi = (translationMode == "Sindhi")
local v25OnlineUrl, v25FileName = M.buildV25WholeTrack(translationMode, index)
local fileName = v25FileName or (isUrdu and ("urdu_surah_"..sID..".mp3") or isHindi and ("hindi_surah_"..sID..".mp3") or isPunjabi and ("punjabi_surah_"..sID..".mp3") or isEnglish and ("english_surah_"..sID..".mp3") or isSindhi and ("sindhi_surah_"..sID..".mp3") or ("reciter_"..reciterKey.."_surah_"..sID..".mp3"))
local localFilePath = downloadDir .. fileName
if v25OnlineUrl and File(localFilePath).exists() and File(localFilePath).length()<1000 then pcall(function() File(localFilePath).delete() end) end
local onlineUrl = v25OnlineUrl or (isUrdu and M.buildUrduSurahUrl(index) or isHindi and M.buildHindiSurahUrl(index) or isPunjabi and M.buildPunjabiSurahUrl(index) or isEnglish and M.buildEnglishSurahUrl(index) or isSindhi and M.buildSindhiSurahUrl(index) or M.buildQuranUrl(currentReciter, index))
local selectedAudioLabel = (V25.modes[translationMode] and V25.modes[translationMode].label) or (isUrdu and "Urdu Tarjuma" or isHindi and "Hindi Tarjuma" or isPunjabi and "Punjabi Tarjuma" or isEnglish and "English Tarjuma" or isSindhi and "Sindhi Tarjuma" or reciters[currentReciter].name)
local playUrl = File(localFilePath).exists() and localFilePath or onlineUrl
local isDownloaded = File(localFilePath).exists()
local bgColor, textColor = M.getThemeColors()
activity.setContentView(loadlayout{
LinearLayout, id="mainLayout", orientation=1, padding="20dp", layout_width=-1, layout_height=-1, gravity="center", backgroundColor=bgColor,
{TextView, text=isDownloaded and "Offline Mode" or "Online Stream", textSize="14sp", layout_marginBottom="10dp", textColor=appColorStr},
{TextView, text=surahName, textSize="26sp", typeface=Typeface.DEFAULT_BOLD, layout_marginBottom="10dp", textColor=appColorStr},
{TextView, text="Reciter / Translation: " .. selectedAudioLabel, textSize="14sp", layout_marginBottom="20dp", textColor=textColor},
{TextView, id="txtSleepTimer", text="", textSize="14sp", textColor="#E91E63", layout_marginBottom="10dp", typeface=Typeface.DEFAULT_BOLD},
{Button, text="📖 Read Surah Text", textSize="14sp", layout_marginBottom="10dp", backgroundColor="#8E24AA", textColor=-1, onClick=function() showReadingMode(index) end},
{Button, text="Ayat-ba-Ayat Mode", textSize="14sp", layout_marginBottom="10dp", backgroundColor="#00695C", textColor=-1, onClick=function() showAyahByAyah(index) end},
{Button, text="Ruku Mode", textSize="14sp", layout_marginBottom="10dp", backgroundColor="#6A1B9A", textColor=-1, onClick=function() showRukuMode(index) end},
{Button, text="Word-by-Word (Hifz)", textSize="14sp", layout_marginBottom="20dp", backgroundColor="#B71C1C", textColor=-1, contentDescription="Word by word memorization mode", onClick=function() showWbwStartDialog(index) end},
{SeekBar, id="skBar", layout_width=-1, layout_marginBottom="10dp"},
{LinearLayout, orientation=0, gravity="center_vertical", layout_width=-1, layout_marginBottom="6dp",
{TextView, text="Speed:", textSize="13sp", textColor=textColor, layout_marginRight="6dp"},
{Spinner, id="playerSpeedSpinner", layout_width=0, layout_weight=1},
{TextView, text="Repeat:", textSize="13sp", textColor=textColor, layout_marginLeft="8dp", layout_marginRight="6dp"},
{Spinner, id="playerRepeatSpinner", layout_width=0, layout_weight=1}
},
{LinearLayout, orientation=0, gravity="center", layout_width=-1,
{Button, text="⏮", textSize="14sp", layout_weight=1, layout_margin="2dp", onClick=function() safeRun("playPrevSurah", playPrevSurah) end},
{Button, text="⏪ "..seekSeconds.."s", textSize="16sp", layout_weight=1, layout_margin="2dp", onClick=function() safeRun("seekRewind", seekRewind) end},
{Button, id="btnPlayPause", text="▶ " .. tr("Play"), textSize="16sp", typeface=Typeface.DEFAULT_BOLD, layout_weight=1.5, layout_margin="2dp", onClick=function() safeRun("togglePlayPause", togglePlayPause) end},
{Button, text=seekSeconds.."s ⏩", textSize="16sp", layout_weight=1, layout_margin="2dp", onClick=function() safeRun("seekForward", seekForward) end},
{Button, text="⏭", textSize="14sp", layout_weight=1, layout_margin="2dp", onClick=function() safeRun("playNextSurah", playNextSurah) end}
},
{Button, id="btnDownload", text=isDownloaded and "🗑 Delete Offline" or "⬇️ Download Surah", textSize="14sp", layout_width=-1, layout_marginTop="20dp", backgroundColor=isDownloaded and "#C62828" or "#1976D2", textColor=-1},
{LinearLayout, orientation=0, gravity="center", layout_marginTop="30dp", layout_width=-1,
{Button, text="Back to List", layout_weight=1, layout_marginRight="10dp", onClick=function() safeRun("showSurahList", showSurahList) end},
{Button, text="Exit App", layout_weight=1, backgroundColor="#C62828", textColor=-1, onClick=function() activity.finish() end}
}
})
M.applyWallpaper(mainLayout, bgColor)
btnDownload.onClick = function() if File(localFilePath).exists() then confirmDelete(localFilePath, function() showPlayer(currentIndex) end) else downloadSurah(onlineUrl, fileName, surahName .. " (" .. selectedAudioLabel .. ")") end end
do
local speedLabels = {"0.75x", "1.0x (Normal)", "1.25x", "1.5x", "2.0x"}
local speedValues = {0.75, 1.0, 1.25, 1.5, 2.0}
local speedIndex = 1
for i,v in ipairs(speedValues) do if math.abs(v - PS.speed) < 0.01 then speedIndex = i - 1 break end end
playerSpeedSpinner.setAdapter(ArrayAdapter(activity, android.R.layout.simple_spinner_dropdown_item, speedLabels))
playerSpeedSpinner.setSelection(speedIndex)
playerSpeedSpinner.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{onItemSelected=function(p,v,pos,id)
savePlaybackSpeed(speedValues[pos+1])
if mp then applyPlaybackSpeed(mp) end
if duaMp then applyPlaybackSpeed(duaMp) end
end})
local repLabels = {"1x", "2x", "3x", "5x", "Loop"}
local repValues = {1, 2, 3, 5, 0}
local repIndex = 0
for i,v in ipairs(repValues) do if v == PS.surahRepeat then repIndex = i - 1 break end end
playerRepeatSpinner.setAdapter(ArrayAdapter(activity, android.R.layout.simple_spinner_dropdown_item, repLabels))
playerRepeatSpinner.setSelection(repIndex)
playerRepeatSpinner.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{onItemSelected=function(p,v,pos,id)
saveSurahRepeatCount(repValues[pos+1])
PS.surahRepeatRem = PS.surahRepeat
end})
end
PS.surahRepeatRem = PS.surahRepeat
if v25OnlineUrl then
PS.externalPlayback=true
PS.externalPreparing=true PS.externalPausePending=false
PS.externalUrl=onlineUrl PS.externalPath=localFilePath PS.externalLabel=selectedAudioLabel
PS.surahRepeatRem=PS.surahRepeat
local function refreshExternalPlayer()
if screen~="player" or not duaMp then return end
pcall(function()
PS.externalPreparing=false
applyPlaybackSpeed(duaMp)
if PS.externalPausePending then
PS.externalPausePending=false
pcall(function() if duaMp.isPlaying() then duaMp.pause() end end)
elseif not duaMp.isPlaying() then
pcall(function() duaMp.start() end)
end
local dur=duaMp.getDuration()
if dur>0 then skBar.setMax(dur); skBar.setProgress(duaMp.getCurrentPosition()) end
if btnPlayPause then btnPlayPause.setText(duaMp.isPlaying() and ("⏸ "..tr("Pause")) or ("▶ "..tr("Play"))) end
M.showPlaybackNotification(surahName,"Translation: "..selectedAudioLabel)
end)
updateTask=Runnable({run=function()
if screen=="player" and PS.externalPlayback and duaMp then
pcall(function() if duaMp.isPlaying() then skBar.setProgress(duaMp.getCurrentPosition()) end end)
handler.postDelayed(updateTask,1000)
end
end})
handler.post(updateTask)
end
local playAgain
playAgain=function()
PS.externalPreparing=true
M.playReliable(playUrl,localFilePath,surahName.." ("..selectedAudioLabel..")",refreshExternalPlayer,function()
completedSurahs[index]=true M.saveCompletedSurahs()
if PS.surahRepeat==0 then
playAgain()
elseif PS.surahRepeatRem>1 then
PS.surahRepeatRem=PS.surahRepeatRem-1
playAgain()
else
PS.surahRepeatRem=PS.surahRepeat
if autoNextMode and currentIndex<#surahNames then playNextSurah()
else
M.stopPlayer(function()
PS.externalPlayback=true
if btnPlayPause then btnPlayPause.setText("▶ "..tr("Play")) end
end)
end
end
end)
end
playAgain()
skBar.setOnSeekBarChangeListener(SeekBar.OnSeekBarChangeListener{onProgressChanged=function(b,pos,fromUser) if fromUser and duaMp then pcall(function() duaMp.seekTo(pos) end) end end})
else
PS.externalPlayback=false PS.externalUrl=nil PS.externalPath=nil PS.externalLabel=nil
M.stopPlayer(function()
playerReady = false
playIntentPending = false
mp = MediaPlayer()
pcall(function() mp.setWakeMode(activity, PowerManager.PARTIAL_WAKE_LOCK) end)
local dsOk,dsErr=pcall(function() mp.setDataSource(playUrl); mp.prepareAsync() end)
if not dsOk then
pcall(function() if mp then mp.release() end end); mp=nil
if v25OnlineUrl then
PS.externalPlayback=true
M.playReliable(playUrl,localFilePath,surahName.." ("..selectedAudioLabel..")",nil,nil)
return
end
Toast.makeText(activity,"Audio source could not be opened: "..tostring(dsErr),1).show()
return
end
mp.setOnErrorListener(MediaPlayer.OnErrorListener{onError=function(p, w, e) if v25OnlineUrl then
pcall(function() if mp then mp.release() end end); mp=nil
PS.externalPlayback=true
M.playReliable(onlineUrl,localFilePath,surahName.." ("..selectedAudioLabel..")",nil,nil)
else Toast.makeText(activity, "Audio error.", 0).show() end
if btnPlayPause then btnPlayPause.setText("▶ " .. tr("Play")) end return true end})
mp.setOnPreparedListener(MediaPlayer.OnPreparedListener{onPrepared=function(p)
applyPlaybackSpeed(p)
skBar.setMax(p.getDuration())
playerReady = true
if playIntentPending then
playIntentPending = false
pcall(function() p.start() end)
pcall(function() if btnPlayPause then btnPlayPause.setText("⏸ " .. tr("Pause")) end end)
M.startSleepTimer()
else
pcall(function() if p.isPlaying() then p.pause() end end)
end
updateTask = Runnable({run = function()
if mp and mp.isPlaying() then
skBar.setProgress(mp.getCurrentPosition())
if targetSleepTime > 0 then
local diff = targetSleepTime - os.time()
if diff > 0 then
local min = math.floor(diff / 60)
local sec = diff % 60
txtSleepTimer.setText(string.format("💤 Auto-stop in: %02d:%02d", min, sec))
else
txtSleepTimer.setText("")
end
else
txtSleepTimer.setText("")
end
end
handler.postDelayed(updateTask, 1000)
end})
handler.post(updateTask)
end})
mp.setOnCompletionListener(MediaPlayer.OnCompletionListener{onCompletion=function()
completedSurahs[index] = true
M.saveCompletedSurahs()
if PS.surahRepeat == 0 then
pcall(function() if mp then mp.seekTo(0) mp.start() end end)
return
end
if PS.surahRepeatRem > 1 then
PS.surahRepeatRem = PS.surahRepeatRem - 1
pcall(function() if mp then mp.seekTo(0) mp.start() end end)
return
end
PS.surahRepeatRem = PS.surahRepeat
if autoNextMode then playNextSurah() else btnPlayPause.setText("▶ " .. tr("Play")) M.cancelNotification() end
end})
skBar.setOnSeekBarChangeListener(SeekBar.OnSeekBarChangeListener{onProgressChanged=function(s, p, f) if f and mp then mp.seekTo(p) end end})
end)
end
end
function onPause() end
function onStop() end
function onDestroy()
pcall(function() M.stopPlayer() end)
pcall(function() M.cancelNotification() end)
pcall(function() wbwStopAudio() end)
end
function onKeyDown(keyCode, event)
if keyCode == 4 then
if screen == "player" then showSurahList() return true
elseif screen == "names" then showMore() return true
elseif screen == "asmanabi" then showMore() return true
elseif screen == "feedback" or screen == "about" then showSettings() return true
elseif screen == "dailyduas" then showHome() return true
elseif screen == "more" then showHome() return true
elseif screen == "azan" then showMore() return true
elseif screen == "azanplayer" or screen == "azanschedule" then showAzan() return true
elseif screen == "progresstracker" or screen == "storagemanager" then showMore() return true
elseif screen == "duaplayer" then showDailyDuas() return true
elseif screen == "para" then showMore() return true
elseif screen == "parasurahs" then showPara() return true
elseif screen == "reading" then showPlayer(currentIndex) return true
elseif screen == "ayahmode" then showPlayer(currentIndex) return true
elseif screen == "rukumode" then showPlayer(currentIndex) return true
elseif screen == "rukuplayer" then showRukuMode(currentIndex) return true
elseif screen == "wbwmode" then wbwStopAudio() showPlayer(WBW.surahIdx) return true
elseif screen == "surahlist" then showHome() return true
elseif screen == "socialmedia" then showSettings() return true
elseif screen == "fullquranlist" then showMore() return true
elseif screen == "fullquranplayer" then showFullQuranScreen() return true
elseif screen == "hadithlist" then showMore() return true
elseif screen == "hadithplayer" then showHadithScreen() return true
elseif screen == "israrlist" then showMore() return true
elseif screen == "israrplayer" then showIsrarTafseerScreen() return true
elseif screen == "nawawilist" then showMore() return true
elseif screen == "nawawiplayer" then showNawawiScreen() return true
elseif screen == "settings" or screen == "tasbeeh" or screen == "bookmarks" then showMore() return true end
end
return false
end
pcall(function() activity.registerReceiver(IntentFilter("quran_majeed_playpause")) end)
pcall(function() for _,pr in ipairs(AZAN_PRAYERS) do M.registerCityAzanReceiver(pr.key) end; scheduleCityAzans() end)
function onActivityResult(requestCode, resultCode, data)
if requestCode==2606 and resultCode==Activity.RESULT_OK and data then
pcall(function()
local spoken=data.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
if spoken and spoken.size()>0 and etHomeSearch then
etHomeSearch.setText(tostring(spoken.get(0)))
etHomeSearch.setSelection(etHomeSearch.length())
end
end)
end
end
function onReceive(context, intent)
pcall(function()
local action = intent.getAction()
local azanPrayer=action and action:match("^quran_majeed_city_azan_(%a+)$")
if azanPrayer then
local trackIndex=prefs.getInt("cityAzanTrack_"..azanPrayer,prefs.getInt("azanDefaultTrack",1))
local track=AZAN_TRACKS[trackIndex]
if track then
local path=M.getAzanLocalPath(trackIndex)
M.playReliable(track.url,path,"Azan "..azanPrayer,function()
M.showPlaybackNotification("Azan - "..azanPrayer,savedCity..", "..savedCountry.." | "..track.name)
end,function() M.cancelNotification() end)
end
pcall(function() scheduleCityAzans() end)
elseif action == "quran_majeed_playpause" then
if mp then
if mp.isPlaying() then
mp.pause()
pcall(function() if btnPlayPause then btnPlayPause.setText("▶ " .. tr("Play")) end end)
else
mp.start()
pcall(function() if btnPlayPause then btnPlayPause.setText("⏸ " .. tr("Pause")) end end)
end
pcall(function() M.showPlaybackNotification(surahNames[currentIndex] or "Quran Majeed", "Reciter: " .. (reciters[currentReciter] and reciters[currentReciter].name or "")) end)
elseif duaMp then
if duaMp.isPlaying() then duaMp.pause() else duaMp.start() end
end
end
end)
end
function onRequestPermissionsResult(requestCode, permissions, grantResults)
end
pcall(function()
if Build.VERSION.SDK_INT >= 23 then
local writePerm = "android.permission.WRITE_EXTERNAL_STORAGE"
local readPerm  = "android.permission.READ_EXTERNAL_STORAGE"
if activity.checkSelfPermission(writePerm) ~= 0 or activity.checkSelfPermission(readPerm) ~= 0 then
local perms = luajava.newArray("java.lang.String", 2)
perms[0] = writePerm
perms[1] = readPerm
activity.requestPermissions(perms, 1001)
end
end
end)
V25.startDateTick()
V25.urduBookTracks = {}
(function()
local t, base = {}, "https://archive.org/download/"
local function pnames(pat, nf)
local o = {}
for k = 1, nf do o[#o + 1] = string.format(pat, k) end
return o
end
local function ssplit(str)
local o = {}
local pos = 1
while true do
local n = str:find("|", pos, true)
if not n then o[#o + 1] = str:sub(pos) break end
o[#o + 1] = str:sub(pos, n - 1)
pos = n + 1
end
return o
end
local SRCS = {hindi = M.hindiTranslationFiles, urdu = M.urduTranslationFiles}
for _, b in ipairs(V25.BOOKS) do
local rest = {}
if b.d then
rest = ssplit(b.d)
if b.pp or b.ss then for i, xn in ipairs(rest) do rest[i] = (b.pp or "") .. xn .. (b.ss or "") end end
elseif b.f then rest = b.f
elseif b.r then rest = SRCS[b.r]()
elseif b.p then rest = pnames(b.p, b.nf)
elseif b.q then
local qs = ssplit(b.q)
for k = 1, b.nf do if qs[k] ~= "" then rest[k] = string.format(b.qp, k) .. qs[k] .. ".mp3" end end
elseif b.u then
local us = ssplit(b.u)
for k = 1, b.nf do rest[k] = string.format("%03d", k) .. us[k] .. (b.h64 and "_64kb.mp3" or ".mp3") end
elseif b.uh then for _, xn in ipairs(SRCS.hindi()) do rest[#rest + 1] = xn:gsub("%.mp3$", "_64kb.mp3") end
elseif b.nf then rest = pnames("%03d.mp3", b.nf) end
if b.o then for _, pair in ipairs(ssplit(b.o)) do local oi, on = pair:match("^(%d+)=(.+)$") rest[tonumber(oi)] = on end end
if b.cp and b.oc then for nn in b.oc:gmatch("%d+") do local oi = tonumber(nn) rest[oi] = string.format(b.cp, oi) end end
local names = {}
if b.x then for _, xn in ipairs(b.x) do names[#names + 1] = xn end end
for _, xn in ipairs(rest) do if xn ~= "" then names[#names + 1] = xn end end
if b.x2 then for _, xn in ipairs(b.x2) do names[#names + 1] = xn end end
local n = #names
for k = 1, n do
local f = names[k]
t[#t + 1] = {book = b.n, lang = b.l, cat = b.c or "book", title = (b.t and ("Surah " .. k .. " of " .. n)) or (k .. ". " .. V25.cleanName(f)),
en = b.l .. " - Part " .. k .. "/" .. n,
audio = base .. b.i .. "/" .. urlEncodeBytes((b.ow and (f:sub(-4) == ".mp3" and f or (f .. ((b.ow2 and b.ow2:find("," .. k .. ",", 1, true)) and "-owaisQadri-owaisQadri.mp3" or "-owaisQadri.mp3")))) or f), src = "archive.org (" .. b.i .. ")",
cacheKey = "bk_" .. b.s .. "_" .. string.format("%03d", k)}
end
end
V25.urduBookTracks = t
end)()
function V25.bookLangRank(lg)
local r = {Urdu=1, Hindi=2, English=3, Arabic=4, Punjabi=5, Chinese=6}
return r[lg] or 9
end
function V25.bookLangList()
local order, seen, out = {}, {}, {}
for _, t in ipairs(V25.urduBookTracks or {}) do
if (t.cat or "book") == "book" then
local lg = t.lang or "Urdu"
if not seen[lg] then seen[lg] = true table.insert(order, lg) end
end
end
table.sort(order, function(a, b)
local ra, rb = V25.bookLangRank(a), V25.bookLangRank(b)
if ra ~= rb then return ra < rb end
return tostring(a) < tostring(b)
end)
for _, lg in ipairs(order) do
local books, bseen, parts = {}, {}, 0
for _, t in ipairs(V25.urduBookTracks or {}) do
if (t.lang or "Urdu") == lg and (t.cat or "book") == "book" then
parts = parts + 1
if not bseen[t.book] then bseen[t.book] = true table.insert(books, t.book) end
end
end
table.insert(out, {lang = lg, books = books, nbooks = #books, parts = parts})
end
return out
end
function V25.booksOfLang(lg)
local books, seen = {}, {}
for _, t in ipairs(V25.urduBookTracks or {}) do
if (t.lang or "Urdu") == lg and (t.cat or "book") == "book" and not seen[t.book] then
seen[t.book] = true table.insert(books, t.book)
end
end
return books
end
function V25.bookPartsCount(b)
local n = 0
for _, t in ipairs(V25.urduBookTracks or {}) do if t.book == b then n = n + 1 end end
return n
end
function V25.bookLangOf(b)
for _, t in ipairs(V25.urduBookTracks or {}) do if t.book == b then return (t.lang or "Urdu") end end
return "Urdu"
end
function showBookLangScreen(lg)
screen = "booklang"
M.stopPlayer()
duaListOverride = nil
V25.duaBackFn = nil
local ok, err = pcall(function()
local bgColor, textColor = M.getThemeColors()
V25.uiTextColor = textColor
activity.setContentView(loadlayout{
LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor,
{LinearLayout, orientation=0, padding="10dp", backgroundColor="#00897B", layout_width=-1, gravity="center_vertical",
{Button, text="< Languages", onClick=function() safeRun("backToLangs", showUrduBooks) end},
{TextView, text="📚 " .. tostring(lg) .. " Books", textSize="16sp", typeface=Typeface.DEFAULT_BOLD, layout_marginLeft="10dp", textColor=-1}
},
{TextView, text="Kisi bhi kitaab par tap karein - uske saare parts khul jayenge. Player Poora Quran jaisa hai: play/pause, seek, speed, download aur offline (.mp3).", textSize="12sp", textColor=textColor, padding="10dp"},
{ScrollView, layout_width=-1, layout_height=0, layout_weight=1,
{LinearLayout, id="booksBox", orientation=1, layout_width=-1, layout_height=-2}
}
})
M.applyWallpaper(mainLayout, bgColor)
local books = V25.booksOfLang(lg)
if #books == 0 then V25.uiRow(booksBox, "Koi kitaab available nahi", "", function() end) return end
for _, bk in ipairs(books) do
local n = V25.bookPartsCount(bk)
V25.uiRow(booksBox, "📖 " .. tostring(bk), tostring(n) .. " parts - tap karein", function() showUrduBookEpisodes(bk) end)
end
end)
if not ok then showErrorDialog("Books screen error", err) end
end
function V25.urduBookNames()
local names, seen = {}, {}
for _, t in ipairs(V25.urduBookTracks or {}) do
if t.book and not seen[t.book] then seen[t.book] = true table.insert(names, t.book) end
end
return names
end
function V25.urduBookEps(b)
local e = {}
for _, t in ipairs(V25.urduBookTracks or {}) do if t.book == b then table.insert(e, t) end end
return e
end
function V25.uiRow(box, title, sub, fn)
local tv = TextView(activity)
tv.setText(tostring(title or "") .. ((sub and sub ~= "") and ("\n" .. tostring(sub)) or ""))
tv.setTextSize(15)
pcall(function() tv.setPadding(24, 26, 24, 26) end)
pcall(function() tv.setBackgroundColor(570425344) end)
pcall(function() local lp = LinearLayout.LayoutParams(-1, -2) lp.setMargins(12, 7, 12, 7) tv.setLayoutParams(lp) end)
pcall(function() local tc = V25.safeTextColor(V25.uiTextColor) if tc then tv.setTextColor(tc) end end)
tv.setOnClickListener(function() safeRun(tostring(title or "row"), fn) end)
box.addView(tv)
return tv
end
function showUrduBooks()
screen = "urdubooks"
M.stopPlayer()
duaListOverride = nil
V25.duaBackFn = nil
local ok, err = pcall(function()
local bgColor, textColor = M.getThemeColors()
V25.uiTextColor = textColor
activity.setContentView(loadlayout{
LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor,
{LinearLayout, orientation=0, padding="10dp", backgroundColor="#00897B", layout_width=-1, gravity="center_vertical",
{Button, text="< Back", onClick=function() safeRun("backToHome", showHome) end},
{TextView, text="📚 اسلامک بکس - Islam Books", textSize="16sp", typeface=Typeface.DEFAULT_BOLD, layout_marginLeft="10dp", textColor=-1}
},
{TextView, text="Islamic kitaabein - Urdu / English / Arabic. Quran ke surah-wise tarjume (25+ aawazein) ab Quran player ke Translations mein hain. Naatein aur Bayanat More menu mein hain.", textSize="12sp", textColor=textColor, padding="10dp"},
{ScrollView, layout_width=-1, layout_height=0, layout_weight=1,
{LinearLayout, id="langBox", orientation=1, layout_width=-1, layout_height=-2}
}
})
M.applyWallpaper(mainLayout, bgColor)
local langs = V25.bookLangList()
if #langs == 0 then V25.uiRow(langBox, "Koi kitaab available nahi", "", function() end) return end
for _, it in ipairs(langs) do
V25.uiRow(langBox, "🌍 " .. tostring(it.lang) .. " (" .. tostring(it.nbooks) .. " kitaabein)",
tostring(it.parts) .. " parts - tap karein", function() showBookLangScreen(it.lang) end)
end
end)
if not ok then showErrorDialog("Islam Books screen error", err) end
end
function showBookCatScreen(cat)
screen = "bookcat"
M.stopPlayer()
duaListOverride = nil
V25.duaBackFn = nil
local ok, err = pcall(function()
local bgColor, textColor = M.getThemeColors()
V25.uiTextColor = textColor
local catName = (cat == "naat") and "Naats / نعتیں (Naat Collections)" or "Bayanat / بیانات (Bayan Collections)"
activity.setContentView(loadlayout{
LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor,
{LinearLayout, orientation=0, padding="10dp", backgroundColor="#00897B", layout_width=-1, gravity="center_vertical",
{Button, text="< More", onClick=function() safeRun("backToMore", showMore) end},
{TextView, text="📖 " .. catName, textSize="16sp", typeface=Typeface.DEFAULT_BOLD, layout_marginLeft="10dp", textColor=-1}
},
{TextView, text="Kisi bhi collection par tap karein - Player Poora Quran jaisa: play/pause, seek, speed, download, offline (.mp3).", textSize="12sp", textColor=textColor, padding="10dp"},
{ScrollView, layout_width=-1, layout_height=0, layout_weight=1,
{LinearLayout, id="booksBox", orientation=1, layout_width=-1, layout_height=-2}
}
})
M.applyWallpaper(mainLayout, bgColor)
local books, seen = {}, {}
for _, t in ipairs(V25.urduBookTracks or {}) do
if t.cat == cat and not seen[t.book] then seen[t.book] = true table.insert(books, t.book) end
end
if #books == 0 then V25.uiRow(booksBox, "Koi audio available nahi", "", function() end) return end
for _, bk in ipairs(books) do
local n = V25.bookPartsCount(bk)
V25.uiRow(booksBox, "📖 " .. tostring(bk), tostring(n) .. " parts - tap karein", function() showUrduBookEpisodes(bk) end)
end
end)
if not ok then showErrorDialog("Category screen error", err) end
end
function showUrduBookEpisodes(b)
screen = "urdubookeps"
M.stopPlayer()
V25.currentBook = b
local eps = V25.urduBookEps(b)
duaListOverride = eps
V25.duaBackFn = function() duaListOverride = nil showUrduBookEpisodes(V25.currentBook) end
local ok, err = pcall(function()
local bgColor, textColor = M.getThemeColors()
V25.uiTextColor = textColor
activity.setContentView(loadlayout{
LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor,
{LinearLayout, orientation=0, padding="10dp", backgroundColor="#00897B", layout_width=-1, gravity="center_vertical",
{Button, text="< Books", onClick=function() safeRun("backToBooks", showUrduBooks) end},
{TextView, text="📖 " .. tostring(b), textSize="15sp", typeface=Typeface.DEFAULT_BOLD, layout_marginLeft="10dp", textColor=-1}
},
{TextView, text=tostring(#eps) .. " episodes - kisi bhi episode par tap karein.", textSize="12sp", textColor=textColor, padding="10dp"},
{ScrollView, layout_width=-1, layout_height=0, layout_weight=1,
{LinearLayout, id="epsBox", orientation=1, layout_width=-1, layout_height=-2}
}
})
M.applyWallpaper(mainLayout, bgColor)
for i, t in ipairs(eps) do
V25.uiRow(epsBox, tostring(i) .. ". " .. tostring(t.title), "Tap karein - play / download / offline",
(function(ix) return function() safeRun("playBookEp", function() showDuaPlayer(ix) end) end end)(i))
end
end)
if not ok then showErrorDialog("Episodes screen error", err) end
end
function showAdvancedSearch()
screen = "advsearch"
M.stopPlayer()
duaListOverride = nil
local ok, err = pcall(function()
local bgColor, textColor = M.getThemeColors()
V25.uiTextColor = textColor
activity.setContentView(loadlayout{
LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor,
{LinearLayout, orientation=0, padding="10dp", backgroundColor="#00695C", layout_width=-1, gravity="center_vertical",
{Button, text="< Back", onClick=function() safeRun("backHome2", showHome) end},
{TextView, text="🔎 Advanced Search", textSize="16sp", typeface=Typeface.DEFAULT_BOLD, layout_marginLeft="10dp", textColor=-1}
},
{LinearLayout, orientation=0, padding="8dp", layout_width=-1, gravity="center_vertical",
{EditText, id="advQuery", hint="Surah, Dua, Kalma, Kitaab, Episode...", layout_weight=1, singleLine=true, textColor=textColor, hintTextColor="#888888"},
{Button, id="advGo", text="Search", layout_marginLeft="6dp"}
},
{TextView, id="advCount", text="Likhein aur Search dabayein", textSize="12sp", textColor=textColor, padding="10dp"},
{ScrollView, layout_width=-1, layout_height=0, layout_weight=1,
{LinearLayout, id="advBox", orientation=1, layout_width=-1, layout_height=-2}
}
})
M.applyWallpaper(mainLayout, bgColor)
advGo.onClick = function() safeRun("advRun", function() V25.advSearchRun(advQuery.getText().toString()) end) end
pcall(function() advQuery.setOnEditorActionListener(function(v, a, e) safeRun("advRun2", function() V25.advSearchRun(advQuery.getText().toString()) end) return true end) end)
end)
if not ok then showErrorDialog("Advanced Search screen error", err) end
end
function V25.advSearchRun(q)
local box = advBox
if not box then return end
pcall(function() box.removeAllViews() end)
local qn = V25.norm(q)
if qn == "" then if advCount then advCount.setText("Kuch likhein (Surah, Dua, Kalma, Kitaab)...") end return end
local n = 0
local function add(tt, sb, fn) n = n + 1 V25.uiRow(box, tt, sb, fn) end
pcall(function()
for i = 1, #surahNames do
if V25.norm(surahNames[i]):find(qn, 1, true) then
add("📗 Surah " .. i .. ": " .. tostring(surahNames[i]), "Poora Quran player kholain", (function(ix) return function() showPlayer(ix) end end)(i))
end
end
end)
pcall(function() if not audioDuasCache and M.buildAudioDuasList then audioDuasCache = M.buildAudioDuasList() end end)
pcall(function()
if audioDuasCache then
for i, d in ipairs(audioDuasCache) do
local hay = tostring(d.title or "") .. " " .. tostring(d.cat or "") .. " " .. tostring(d.en or "") .. " " .. tostring(d.ur or "")
if V25.norm(hay):find(qn, 1, true) then
add("🔊 " .. tostring(d.title), tostring(d.cat or ""), (function(ix) return function() duaListOverride = nil showDuaPlayer(ix) end end)(i))
end
end
end
end)
pcall(function()
for _, t in ipairs(V25.urduBookTracks or {}) do
local hay = tostring(t.book or "") .. " " .. tostring(t.title or "")
if V25.norm(hay):find(qn, 1, true) then
add("📖 " .. tostring(t.title), "Kitaab: " .. tostring(t.book), (function(bk) return function() showUrduBookEpisodes(bk) end end)(t.book))
end
end
end)
pcall(function()
if reciters then
for _, r in ipairs(reciters) do
local nm = tostring(type(r) == "table" and (r.name or r[1] or "") or r)
if nm ~= "" and V25.norm(nm):find(qn, 1, true) then
add("🎙️ " .. nm, "Qari - Poora Quran screen kholein", function() safeRun("openFQ", showFullQuranScreen) end)
end
end
end
end)
if advCount then
if n == 0 then advCount.setText("Kuch nahi mila: " .. tostring(q)) else advCount.setText(tostring(n) .. " nataij mil gaye (tap karein)") end
end
end
safeRun("App start - Home screen", showHome)