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

--------------------------------------------------
-- QURAN MAJEED v2.0 - Simplified UI + Reciter-name-based fix + Accessibility labels
-- Lead: Numan Khan
--------------------------------------------------

--------------------------------------------------
-- GLOBAL VARIABLES & APP STATE
--------------------------------------------------
local mp = nil
local screen = "home"
local currentIndex = 1
local currentReciter = 1
local autoNextMode = true
local isPaused = false
local playbackSpeed = 1.0
local sleepTimerMinutes = 0
local seekSeconds = 10
local targetSleepTime = 0

local handler = Handler(Looper.getMainLooper())
local updateTask = nil

-- FIX: pehle files getExternalFilesDir (app-private folder) mein ja rahi thi,
-- isliye phone ke normal Downloads folder/file manager mein nazar nahi aati thi.
-- Ab public Downloads directory use ho rahi hai taake downloads Downloads app/
-- file manager mein bhi show hon.
local publicDownloadsRoot = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS).getAbsolutePath()

local downloadDir = publicDownloadsRoot .. "/Quran_Files/"
if not File(downloadDir).exists() then File(downloadDir).mkdirs() end

local duaAudioDir = publicDownloadsRoot .. "/Dua_Audio/"
if not File(duaAudioDir).exists() then File(duaAudioDir).mkdirs() end

local paraAudioDir = publicDownloadsRoot .. "/Para_Audio/"
if not File(paraAudioDir).exists() then File(paraAudioDir).mkdirs() end

local duaMp = nil

-- Fixed app appearance (Language/Theme/Color/Wallpaper pickers removed on request)
local appColorStr = "#1B5E20"
local function getThemeColors() return "#FFFFFF", "#000000" end
local function applyWallpaper(view, bgColor) if view then view.setBackgroundColor(Color.parseColor(bgColor)) end end
local function tr(text) return text end

--------------------------------------------------
-- SHARED PREFERENCES & DATA
--------------------------------------------------
local prefs = activity.getSharedPreferences("QuranAppPrefs", 0)

-- PROGRESS TRACKER data (jo Surah pura sun li, aur Ayat-ba-Ayat/Ruku mein
-- aakhri position - taake qari sahab track kar sakein bachon ne kahan tak
-- kiya, aur resume kiya ja sake)
local completedSurahsStr = prefs.getString("completedSurahs", "")
local completedSurahs = {}
if completedSurahsStr ~= "" then for s in string.gmatch(completedSurahsStr, "([^,]+)") do completedSurahs[tonumber(s)] = true end end
local function saveCompletedSurahs()
  local arr = {}
  for k,v in pairs(completedSurahs) do if v then table.insert(arr, k) end end
  prefs.edit().putString("completedSurahs", table.concat(arr, ",")).apply()
end

local function loadPairMap(key)
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
local function savePairMap(key, map)
  local parts = {}
  for k, v in pairs(map) do table.insert(parts, k .. ":" .. v) end
  prefs.edit().putString(key, table.concat(parts, ",")).apply()
end

local lastAyahProgress = loadPairMap("lastAyahProgress")
local function saveLastAyahProgress(surahIdx, ayahNum)
  lastAyahProgress[surahIdx] = ayahNum
  savePairMap("lastAyahProgress", lastAyahProgress)
end

local lastRukuProgress = loadPairMap("lastRukuProgress")
local function saveLastRukuProgress(surahIdx, rukuIdx)
  lastRukuProgress[surahIdx] = rukuIdx
  savePairMap("lastRukuProgress", lastRukuProgress)
end

local tasbeehCount = prefs.getInt("activeCount", 0)
local tasbeehTarget = prefs.getInt("activeTarget", 33)
local currentWazeefaIndex = prefs.getInt("activeWazeefa", 0)
local tasbeehBeepEnabled = prefs.getBoolean("tasbeehBeep", true)
local tasbeehVibrateEnabled = prefs.getBoolean("tasbeehVibrate", true)
local lifetimeZikrTotal = prefs.getInt("lifetimeZikrTotal", 0)
local lastPlayedSurah = prefs.getInt("lastSurah", 1)
local readingFontSize = prefs.getInt("readingFontSize", 22)

local savedCity = prefs.getString("userCity", "Abbottabad")
local savedCountry = prefs.getString("userCountry", "Pakistan")
local prayerFajr = prefs.getString("pFajr", "04:10")
local prayerDhuhr = prefs.getString("pDhuhr", "12:15")
local prayerAsr = prefs.getString("pAsr", "16:45")
local prayerMaghrib = prefs.getString("pMaghrib", "19:10")
local prayerIsha = prefs.getString("pIsha", "20:30")
local savedHijriDate = prefs.getString("hijriDate", "Update location for Hijri Date")

--------------------------------------------------
-- Small helper: sanitize a reciter name into a safe filename fragment
--------------------------------------------------
local function slug(s)
  local out = tostring(s):gsub("%s+", "_"):gsub("[^%w_]", "")
  if out == "" then out = "reciter" end
  return out
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

-- FIX (v2.1): Prayer times pehle sirf ek dafa (manual "Update Location"
-- click par) fetch hoti thin aur phir HAMESHA ke liye prefs mein cache ho
-- jati thin - is liye din chhote/bare hone se bhi timings kabhi update
-- nahi hoti thin (roz wahi purani values dikhti thin). Ab app ye track
-- karta hai ke aakhri dafa kis TAREEKH ko fetch hui thi - agar aaj ki
-- tareekh se mismatch ho, khud-ba-khud (bina button dabaye) background
-- mein dobara fetch ho jati hai.
local lastPrayerFetchDate = prefs.getString("lastPrayerFetchDate", "")
local function todayDateString()
  return os.date("%Y-%m-%d")
end
local function currentBatteryPercent()
  local pct = -1
  pcall(function()
    local bm = activity.getSystemService(Context.BATTERY_SERVICE)
    pct = bm.getIntProperty(4) -- BatteryManager.BATTERY_PROPERTY_CAPACITY
  end)
  return pct
end

-- Aladhan API se prayer times fetch karta hai - "Update Location" button
-- (manual) aur auto-refresh (roz khud-ba-khud) dono isay reuse karte hain.
-- FIX (v2.1): http:// ko https:// kar diya (kuch networks/devices plain
-- HTTP block/degrade karte hain, jis se fetch kabhi kabhi fail hoti thi).
local function fetchPrayerTimes(c, cntry, onDone)
  Thread(Runnable{
    run=function()
      local success, result = pcall(function()
        local urlStr = "https://api.aladhan.com/v1/timingsByCity?city="..URLEncoder.encode(c).."&country="..URLEncoder.encode(cntry).."&method=1"
        local conn = URL(urlStr).openConnection()
        conn.setConnectTimeout(10000) conn.setReadTimeout(15000)
        local reader = BufferedReader(InputStreamReader(conn.getInputStream()))
        local res = "" local line = reader.readLine()
        while line do res = res..line line = reader.readLine() end
        reader.close() return res
      end)
      activity.runOnUiThread(Runnable{
        run=function()
          local ok = false
          if success and result then
            local f = result:match('"Fajr":"(.-)"')
            local d = result:match('"Dhuhr":"(.-)"')
            local a = result:match('"Asr":"(.-)"')
            local m = result:match('"Maghrib":"(.-)"')
            local i = result:match('"Isha":"(.-)"')
            local hjDay = result:match('"hijri":{.-"day":"(.-)"')
            local hjMonth = result:match('"month":{.-"en":"(.-)"')
            local hjYear = result:match('"year":"(.-)"')
            if f then
              savedCity = c savedCountry = cntry
              prayerFajr = f prayerDhuhr = d prayerAsr = a prayerMaghrib = m prayerIsha = i
              if hjDay and hjMonth and hjYear then savedHijriDate = hjDay.." "..hjMonth.." "..hjYear else savedHijriDate = "Hijri Fetch Error" end
              lastPrayerFetchDate = todayDateString()
              prefs.edit().putString("userCity", c).putString("userCountry", cntry).putString("pFajr", f).putString("pDhuhr", d).putString("pAsr", a).putString("pMaghrib", m).putString("pIsha", i).putString("hijriDate", savedHijriDate).putString("lastPrayerFetchDate", lastPrayerFetchDate).apply()
              ok = true
            end
          end
          if onDone then onDone(ok) end
        end
      })
    end
  }).start()
end

local function openLinkAndClose(urlStr)
  pcall(function() activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(urlStr))) activity.finish() end)
end

--------------------------------------------------
-- QURAN, WAZAIF & 99 NAMES DATA
--------------------------------------------------

-- Reciters: DI reciter hardcoded (verified) at index 1, baaki live-fetch se aata hai
local reciters = {
  {name="Qari Asad Attari (Dawat-e-Islami)", url="https://data2.dawateislami.net/download/tilawat-e-quran/ur/mp3/2018/", isDI=true},
  {name="Mishary Rashid Alafasy", url="https://server8.mp3quran.net/afs/"},
  {name="Abdul Basit", url="https://server6.mp3quran.net/basit/"},
  {name="Saad Al-Ghamdi", url="https://server7.mp3quran.net/s_gmd/"},
  {name="Maher Al Meaqli", url="https://server12.mp3quran.net/maher/"},
  {name="Saud Al-Shuraim", url="https://server7.mp3quran.net/shur/"},
  {name="Mahmoud Khalil Al-Hussary", url="https://server13.mp3quran.net/husr/"},
  {name="Mohammed Siddiq Al-Minshawi", url="https://server10.mp3quran.net/minsh/"},
}

local function buildQuranUrl(reciterIdx, surahIdx)
  local r = reciters[reciterIdx]
  if r.isDI then
    local diId = 59423 + surahIdx
    return r.url .. diId .. ".mp3"
  else
    return r.url .. string.format("%03d", surahIdx) .. ".mp3"
  end
end

-- Find a reciter's current index by NAME (index-based tracking caused the
-- "wrong reciter voice / mismatched downloads" bug when the live list reordered)
local function findReciterIndexByName(name)
  if not name or name == "" then return 1 end
  for i, r in ipairs(reciters) do
    if r.name == name then return i end
  end
  return 1
end

-- LIVE RECITERS FETCHER (mp3quran.net official API - 50+ full-Quran reciters)
local function fetchRecitersFromAPI()
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
        if #newList >= 49 then break end -- 49 + DI = 50
      end
    end
  end)
  if #newList == 0 then return nil end
  return newList
end

local function saveRecitersCache(list)
  local parts = {}
  for _, r in ipairs(list) do
    if not r.isDI then table.insert(parts, r.name.."|"..r.url) end
  end
  prefs.edit().putString("recitersCache", table.concat(parts, ";;")).apply()
end
local function loadRecitersCache()
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

local diReciterEntry = reciters[1] -- backup DI entry reference
local cachedList = loadRecitersCache()
if cachedList then
  local merged = {diReciterEntry}
  for _, r in ipairs(cachedList) do table.insert(merged, r) end
  reciters = merged
end

-- Resolve saved reciter selection by NAME (survives reordering across sessions)
local savedReciterName = prefs.getString("lastReciterName", "")
currentReciter = findReciterIndexByName(savedReciterName)
local lastPlayedReciter = currentReciter

Thread(Runnable{run=function()
  local liveList = fetchRecitersFromAPI()
  if liveList then
    -- capture what's currently selected BEFORE the list changes, so playback
    -- doesn't silently jump to a different reciter mid-session
    local previouslySelectedName = reciters[currentReciter] and reciters[currentReciter].name or ""
    local merged = {diReciterEntry}
    for _, r in ipairs(liveList) do table.insert(merged, r) end
    handler.post(Runnable{run=function()
      reciters = merged
      saveRecitersCache(liveList)
      currentReciter = findReciterIndexByName(previouslySelectedName)
    end})
  end
end}).start()

local surahNames = {"Al-Fatihah","Al-Baqarah","Al-Imran","An-Nisa","Al-Ma'idah","Al-An'am","Al-A'raf","Al-Anfal","At-Tawbah","Yunus","Hud","Yusuf","Ar-Ra'd","Ibrahim","Al-Hijr","An-Nahl","Al-Isra","Al-Kahf","Maryam","Ta-Ha","Al-Anbiya","Al-Hajj","Al-Mu'minun","An-Nur","Al-Furqan","Ash-Shu'ara","An-Naml","Al-Qasas","Al-Ankabut","Ar-Rum","Luqman","As-Sajdah","Al-Ahzab","Saba","Fatir","Ya-Sin","As-Saffat","Sad","Az-Zumar","Ghafir","Fussilat","Ash-Shura","Az-Zukhruf","Ad-Dukhan","Al-Jathiyah","Al-Ahqaf","Muhammad","Al-Fath","Al-Hujurat","Qaf","Adh-Dhariyat","At-Tur","An-Najm","Al-Qamar","Ar-Rahman","Al-Waqi'ah","Al-Hadid","Al-Mujadilah","Al-Hashr","Al-Mumtahanah","As-Saff","Al-Jumu'ah","Al-Munafiqun","At-Taghabun","At-Talaq","At-Tahrim","Al-Mulk","Al-Qalam","Al-Haqqah","Al-Ma'arij","Nuh","Al-Jinn","Al-Muzzammil","Al-Muddaththir","Al-Qiyamah","Al-Insan","Al-Mursalat","An-Naba","An-Nazi'at","Abasa","At-Takwir","Al-Infitar","Al-Mutaffifin","Al-Inshiqaq","Al-Buruj","At-Tariq","Al-A'la","Al-Ghashiyah","Al-Fajr","Al-Balad","Ash-Shams","Al-Layl","Ad-Duha","Ash-Sharh","At-Tin","Al-Alaq","Al-Qadr","Al-Bayyinah","Az-Zalzalah","Al-Adiyat","Al-Qari'ah","At-Takathur","Al-Asr","Al-Humazah","Al-Fil","Quraysh","Al-Ma'un","Al-Kawthar","Al-Kafirun","An-Nasr","Al-Masad","Al-Ikhlas","Al-Falaq","An-Nas"}

-- Juz/Para -> Starting Surah mapping (standard division)
local paraSurahStart = {1,2,2,3,4,4,5,6,7,8,9,11,12,14,17,18,21,23,25,27,29,33,36,39,41,46,51,58,67,78}

-- Standard ayah count per Surah (Hafs/Uthmani) - zaroori hai Ayat-ba-Ayat mode ke liye
local surahAyahCounts = {7,286,200,176,120,165,206,75,129,109,123,111,43,52,99,128,111,110,98,135,112,78,118,64,77,227,93,88,69,60,34,30,73,54,45,83,182,88,75,85,54,53,89,59,37,35,38,29,18,45,60,49,62,55,78,96,29,22,24,13,14,11,11,18,12,12,30,52,52,44,28,28,20,56,40,31,50,40,46,42,29,19,36,25,22,17,19,26,30,20,15,21,11,8,8,19,5,8,8,11,11,8,3,9,5,4,7,3,6,3,5,4,5,6}

--------------------------------------------------
-- URDU TRANSLATION (v2.1) - Arabic recitation + Urdu tarjuma COMBINED in
-- ek hi file per Surah (archive.org: complete-quran-with-urdu-translation-
-- mishary-rashid-alafasy). Filenames formula se nahi bantay (typos/spacing
-- quirks hain asal source mein), is liye 114/114 individually verify kar
-- ke yahan likhi gayi hain, taake koi 404 na aaye.
--------------------------------------------------
local URDU_TRANSLATION_BASE = "https://archive.org/download/complete-quran-with-urdu-translation-mishary-rashid-alafasy/"
local urduTranslationFiles = {
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
local function buildUrduSurahUrl(surahIdx)
  local fn = urduTranslationFiles[surahIdx]
  if not fn then return nil end
  return URDU_TRANSLATION_BASE .. fn:gsub(" ", "%%20")
end

-- NAYA (v2.1): Hindi Translation - Arabic recitation (Sheikh Abdur Rehman
-- Al Sudes) + Hindi tarjuma awaz (Younus Khan) COMBINED, ek hi file per
-- Surah (archive.org: The_Noble_Quran_With_Hindi_Translation-Audio_MP3_HQ) -
-- 114/114 verified. Filenames mein Arabic characters bhi hain, is liye
-- proper byte-level URL-encoding zaroori hai (sirf space nahi).
local HINDI_TRANSLATION_BASE = "https://archive.org/download/The_Noble_Quran_With_Hindi_Translation-Audio_MP3_HQ/"
local function urlEncodeBytes(str)
  return (str:gsub("[^%w%-%.%_%~]", function(c) return string.format("%%%02X", string.byte(c)) end))
end
local hindiTranslationFiles = {
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
local function buildHindiSurahUrl(surahIdx)
  local fn = hindiTranslationFiles[surahIdx]
  if not fn then return nil end
  return HINDI_TRANSLATION_BASE .. urlEncodeBytes(fn)
end

-- NAYA (v2.1): Punjabi Translation - Arabic recitation (Qari Khushi
-- Muhammad-ul-Azhari) + Punjabi tarjuma (Hidayatullah, awaz Aziz Malik)
-- COMBINED, ek hi file per Surah (archive.org:
-- AlQuranWithPunjabiTranslation) - 114/114 verified.
local PUNJABI_TRANSLATION_BASE = "https://archive.org/download/AlQuranWithPunjabiTranslation/"
local punjabiTranslationFiles = {
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
local function buildPunjabiSurahUrl(surahIdx)
  local fn = punjabiTranslationFiles[surahIdx]
  if not fn then return nil end
  return PUNJABI_TRANSLATION_BASE .. urlEncodeBytes(fn)
end

-- NAYA (v2.1): English Translation - Recitation + English tarjuma (Ibrahim
-- Walk, Saheeh International) COMBINED, ek hi file per Surah (archive.org:
-- quran-english-translation-audio) - 114/114 verified.
local ENGLISH_TRANSLATION_BASE = "https://archive.org/download/quran-english-translation-audio/"
local englishTranslationFiles = {
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
local function buildEnglishSurahUrl(surahIdx)
  local fn = englishTranslationFiles[surahIdx]
  if not fn then return nil end
  return ENGLISH_TRANSLATION_BASE .. urlEncodeBytes(fn)
end

local translationMode = prefs.getString("translationMode", "Off")  -- "Off", "Urdu", "Hindi", "Punjabi", or "English"
local function saveTranslationMode(v)
  translationMode = v
  prefs.edit().putString("translationMode", v).apply()
end

-- Ayat-ba-Ayat audio: per-ayah files sirf ek fixed, verified reciter (Alafasy)
-- ke liye reliably available hain (everyayah.com) - app ke dynamic 50+ reciter
-- list (jo poori Surah files deti hai) mein per-ayah files available nahi hain,
-- is liye Ayat-ba-Ayat hamesha isi reciter ki awaz mein hoga
local ayahAudioDir = duaAudioDir:gsub("Dua_Audio", "Ayah_Audio")
if not File(ayahAudioDir).exists() then File(ayahAudioDir).mkdirs() end
local function buildAyahUrl(surahIdx, ayahNum)
  return "https://everyayah.com/data/Alafasy_128kbps/" .. string.format("%03d%03d", surahIdx, ayahNum) .. ".mp3"
end
local function getAyahAudioLocal(surahIdx, ayahNum)
  return ayahAudioDir .. "s" .. surahIdx .. "_a" .. ayahNum .. ".mp3"
end
-- NAYA (v2.1): Urdu per-Ayat tarjuma (everyayah.com: translations/
-- urdu_shamshad_ali_khan_46kbps) - bilkul wahi %03d%03d numbering jo
-- Arabic per-Ayat audio mein hai (verified), is liye Ayat-ba-Ayat aur
-- Ruku dono mode isay reuse kar sakte hain.
local function buildUrduAyahUrl(surahIdx, ayahNum)
  return "https://everyayah.com/data/translations/urdu_shamshad_ali_khan_46kbps/" .. string.format("%03d%03d", surahIdx, ayahNum) .. ".mp3"
end
local function getUrduAyahAudioLocal(surahIdx, ayahNum)
  return ayahAudioDir .. "urdu_s" .. surahIdx .. "_a" .. ayahNum .. ".mp3"
end
-- NAYA (v2.1): Farhat Hashmi ki Urdu tarjuma (everyayah.com: translations/
-- urdu_farhat_hashmi) - dusri Urdu awaz, bilkul wahi per-Ayat numbering.
local function buildFarhatAyahUrl(surahIdx, ayahNum)
  return "https://everyayah.com/data/translations/urdu_farhat_hashmi/" .. string.format("%03d%03d", surahIdx, ayahNum) .. ".mp3"
end
local function getFarhatAyahAudioLocal(surahIdx, ayahNum)
  return ayahAudioDir .. "farhat_s" .. surahIdx .. "_a" .. ayahNum .. ".mp3"
end
local urduVoice = prefs.getString("urduVoice", "Shamshad")  -- "Shamshad" or "Farhat"
local function saveUrduVoice(v)
  urduVoice = v
  prefs.edit().putString("urduVoice", v).apply()
end
-- Ayat-ba-Ayat/Ruku mode ke liye: currently selected Urdu voice ke mutabiq
-- sahi URL/local-path jodi wapis karta hai
local function currentUrduAyahPair(surahIdx, n)
  if urduVoice == "Farhat" then
    return buildFarhatAyahUrl(surahIdx, n), getFarhatAyahAudioLocal(surahIdx, n)
  else
    return buildUrduAyahUrl(surahIdx, n), getUrduAyahAudioLocal(surahIdx, n)
  end
end
-- NAYA (v2.1): English per-Ayat tarjuma (everyayah.com: English/
-- Sahih_Intnl_Ibrahim_Walk_192kbps) - wahi Ibrahim Walk ki awaz jo
-- Surah-level English mein hai, verified.
local function buildEnglishAyahUrl(surahIdx, ayahNum)
  return "https://everyayah.com/data/English/Sahih_Intnl_Ibrahim_Walk_192kbps/" .. string.format("%03d%03d", surahIdx, ayahNum) .. ".mp3"
end
local function getEnglishAyahAudioLocal(surahIdx, ayahNum)
  return ayahAudioDir .. "english_s" .. surahIdx .. "_a" .. ayahNum .. ".mp3"
end

-- FIX (crash): "Download All Ayahs" pehle DownloadManager use kar raha tha -
-- ek Surah ke sath sath sau se zyada chhoti files ke liye DownloadManager ko
-- baar baar (loop mein) call karna, phir har ek ke liye poll karna, device ke
-- system resources (aur uske sath Jieshuo/TalkBack) ko overload kar deta tha,
-- jis se CSR crash/hang ho raha tha. Ab ek halka, seedha HTTP download hota
-- hai (koi DownloadManager, koi notification, koi system-service overhead
-- nahi) - yeh chhoti files ke liye kaafi zyada reliable aur halka hai.
--
-- FIX (line 279 error): mera pehla byte-array banane ka tareeqa
-- (luajava.newArray / luajava.newInstance) is AndroLua build mein kaam nahi
-- kar raha tha. AndroLua_pro ke apne source code (bin.lua) mein sahi tareeqa
-- mila: "byte[size]" syntax, aur ek built-in "LuaUtil.copyFile(input, output)"
-- utility jo yeh kaam khud handle karti hai - ab pehle wahi try hoti hai.
local function makeByteBuffer(size)
  local ok, buf = pcall(function() return byte[size] end)
  if ok and buf then return buf end
  local ok2, buf2 = pcall(function() return luajava.newArray("byte", size) end)
  if ok2 and buf2 then return buf2 end
  return nil
end

local lastDownloadError = ""
local function directDownload(urlStr, destPath)
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
      -- Fallback: manual copy loop with the correct byte[] array syntax
      local buffer = makeByteBuffer(4096)
      if not buffer then error("byte buffer creation failed - no working array API found") end
      local len = inStream.read(buffer)
      while len and len > 0 do
        outStream.write(buffer, 0, len)
        len = inStream.read(buffer)
      end
    end
  end)
  -- FIX (severe crash/reboot on bulk download): pehle yeh cleanup lines
  -- upar wale pcall ke ANDAR, aakhir mein thi - agar koi download beech mein
  -- fail hota (timeout, network hiccup - jo 100+ requests mein laazmi kabhi
  -- na kabhi hota hai) to connection/stream kabhi band nahi hoti thi. Itni
  -- saari leaked connections jama hoke poore device ko unstable/crash kar
  -- deti thin. Ab cleanup HAMESHA hota hai, chahe download kamyab ho ya na ho.
  pcall(function() if outStream then outStream:flush() end end)
  pcall(function() if outStream then outStream:close() end end)
  pcall(function() if inStream then inStream:close() end end)
  pcall(function() if conn then conn:disconnect() end end)
  if not ok then
    lastDownloadError = tostring(err)
    pcall(function() File(destPath).delete() end)
    return false
  end
  -- Chhoti/khaali file ka matlab download adhoori/kharab hui - usay valid nahi maante
  local f = File(destPath)
  if not f.exists() or f.length() < 1000 then
    lastDownloadError = "file too small (" .. tostring(f.exists() and f.length() or 0) .. " bytes) - likely truncated"
    pcall(function() f.delete() end)
    return false
  end
  return true
end

-- Bulk downloads (100+ files) ko EK lambi background thread mein loop karne
-- ki bajaye, har ayat ke liye alag CHHOTI thread banate hain, aur agli sirf
-- pichli poori khatam hone ke baad, main thread se thodi der (delay) ke sath
-- shuru karte hain. Isse system/accessibility-service ko har download ke
-- baad "saans lene" ka pura mauka milta hai - lambi, mustaqil background
-- thread na hone se watchdog/ANR ka khatra bohot kam ho jata hai.
local function downloadSequentially(items, index, doneCount, onProgress, onComplete)
  if index > #items then
    onComplete(doneCount)
    return
  end
  local item = items[index]
  Thread(Runnable{run=function()
    pcall(function() Thread.currentThread():setPriority(Thread.MIN_PRIORITY) end)
    local success = File(item.path).exists()
    if not success then
      success = directDownload(item.url, item.path)
    end
    local newDone = doneCount + (success and 1 or 0)
    handler.postDelayed(function()
      pcall(onProgress, newDone, index)
      downloadSequentially(items, index + 1, newDone, onProgress, onComplete)
    end, 40)
  end}).start()
end

local paraNames = {}
for i=1,30 do paraNames[i] = "Para " .. i .. " (" .. surahNames[paraSurahStart[i]] .. " se)" end

local wazaifCategories = {"General Zikr", "Morning Azkar", "Evening Azkar", "Protection", "Durood Shareef"}
local wazaifLabels = {
  "Bismillah", "SubhanAllah", "Alhamdulillah", "Allahu Akbar", "La Ilaha Illallah", "Astaghfirullah",
  "SubhanAllahi Wa Bihamdihi", "Hasbunallahu Wa Ni'mal Wakeel", "La Hawla Wa La Quwwata",
  "Ayatul Kursi", "Durood-e-Ibrahimi"
}
local wazaifArabicText = {
  "بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ", "سُبْحَانَ اللَّهِ", "الْحَمْدُ لِلَّهِ", "اللَّهُ أَكْبَرُ", "لَا إِلَٰهَ إِلَّا اللَّهُ", "أَسْتَغْفِرُ اللَّهَ",
  "سُبْحَانَ اللَّهِ وَبِحَمْدِهِ", "حَسْبُنَا اللَّهُ وَنِعْمَ الْوَكِيلُ", "لَا حَوْلَ وَلَا قُوَّةَ إِلَّا بِاللَّهِ",
  "اللَّهُ لَا إِلَٰهَ إِلَّا هُوَ الْحَيُّ الْقَيُّومُ", "اللَّهُمَّ صَلِّ عَلَى مُحَمَّدٍ وَعَلَى آلِ مُحَمَّدٍ"
}

local dailyAyahs = {
  {ar="فَإِنَّ مَعَ الْعُسْرِ يُسْرًا", ur="پس بے شک مشکل کے ساتھ آسانی ہے", ref="Surah Ash-Sharh: 5"},
  {ar="وَاسْتَعِينُوا بِالصَّبْرِ وَالصَّلَاةِ", ur="اور صبر اور نماز کے ذریعے مدد طلب کرو", ref="Surah Al-Baqarah: 45"},
  {ar="فَاذْكُرُونِي أَذْكُرْكُمْ", ur="پس تم مجھے یاد رکھو، میں تمہیں یاد رکھوں گا", ref="Surah Al-Baqarah: 152"}
}

-- Blessed Names of Prophet Muhammad (peace be upon him) - jaise Quran ke
-- dono side par likhe hote hain, waise hi screen par show honge
local asmaNabi = {
  {ar="مُحَمَّد", ro="Muhammad", ur="بہت زیادہ تعریف کیا گیا"},
  {ar="أَحْمَد", ro="Ahmad", ur="سب سے زیادہ تعریف کرنے والا"},
  {ar="الْمَاحِي", ro="Al-Mahi", ur="کفر مٹانے والا"},
  {ar="الْحَاشِر", ro="Al-Hashir", ur="جس کے بعد لوگ حشر کے لیے جمع ہوں گے"},
  {ar="الْعَاقِب", ro="Al-Aqib", ur="سب سے آخری نبی"},
  {ar="رَسُول الله", ro="Rasul Allah", ur="اللہ کے رسول"},
  {ar="النَّبِيّ", ro="An-Nabi", ur="نبی"},
  {ar="حَبِيب الله", ro="Habib Allah", ur="اللہ کے پیارے"},
  {ar="المُصْطَفَى", ro="Al-Mustafa", ur="چنا ہوا"},
  {ar="الأمِين", ro="Al-Ameen", ur="امانت دار"},
  {ar="الصَّادِق", ro="As-Sadiq", ur="سچا"},
  {ar="سِرَاجًا مُنِيرًا", ro="Sirajan Muneera", ur="روشن چراغ"},
  {ar="رَحْمَة لِلْعَالَمِين", ro="Rahmatan lil-Alameen", ur="جہانوں کے لیے رحمت"},
  {ar="شَاهِد", ro="Shahid", ur="گواہی دینے والا"},
  {ar="مُبَشِّر", ro="Mubashshir", ur="خوشخبری دینے والا"},
  {ar="نَذِير", ro="Nazir", ur="ڈرانے والا"},
  {ar="دَاعِيًا إِلَى الله", ro="Da'iyan ilAllah", ur="اللہ کی طرف بلانے والا"},
  {ar="طٰه", ro="Taha", ur="پاک، پاکیزہ"},
  {ar="يٰسٓ", ro="Ya-Seen", ur="اے انسانوں کے سردار"},
  {ar="خَاتَم النَّبِيِّين", ro="Khatam-un-Nabiyyeen", ur="نبیوں کے آخری"}
}

-- 99 Names of Allah (each with per-name audio for individual play)
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

--------------------------------------------------
-- HOME "SPOTLIGHT" - jaise Quran app open karte hi kabhi surah ka naam, kabhi
-- Allah ka naam, kabhi Nabi ka naam, kabhi ayat likhi nazar aati hai - ek hi
-- jagah par, har baar app kholne par NAYA text (sirf roz nahi, har open par)
--------------------------------------------------
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
local function pickSpotlight()
  local idx = prefs.getInt("spotlightIndex", 0)
  local item = spotlightList[(idx % #spotlightList) + 1]
  prefs.edit().putInt("spotlightIndex", idx + 1).apply()
  return item
end

--------------------------------------------------
-- DAILY MASNOON DUAS DATA
--------------------------------------------------
-- NOTE: audio="" means no verified working audio URL has been added yet for
-- that dua. Individually-labeled verified audio per hadith-dua is hard to find
-- as a direct freely-linkable file, so per your instruction these entries use
-- pure hadith wording only (no Quran ayat text). A "Full Masnoon Duas Audio"
-- button below plays/downloads the complete verified Hisnul Muslim recording
-- instead, so users still get audio even without a per-dua link.
local dailyDuas = {
  {cat="Khaana Peena", title="Khana Khane Ke Baad", ar="الْحَمْدُ لِلَّهِ الَّذِي أَطْعَمَنِي هَٰذَا وَرَزَقَنِيهِ مِنْ غَيْرِ حَوْلٍ مِنِّي وَلَا قُوَّةٍ", ur="تمام تعریفیں اللہ کے لیے جس نے مجھے یہ کھلایا اور رزق دیا", tip="Khana khatam hone ke baad parhein", audio="https://archive.org/download/islamic-dua-in-audio/dua-after-eating.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Khaana Peena", title="Doodh Peene Ke Baad", ar="اللَّهُمَّ بَارِكْ لَنَا فِيهِ وَزِدْنَا مِنْهُ", ur="اے اللہ اس میں برکت دے اور اس سے زیادہ عطا فرما", tip="Doodh peene ke khaas baad ki dua", audio="", src=""},
  {cat="Sona Uthna", title="Sone Se Pehle Ki Dua", ar="بِاسْمِكَ اللَّهُمَّ أَمُوتُ وَأَحْيَا", ur="اے اللہ تیرے نام سے مرتا اور جیتا ہوں", tip="Bistar par lait kar dayin karwat par parhein (Sahih Bukhari)", audio="", src=""},
  {cat="Sona Uthna", title="Neend Se Uthne Ki Dua", ar="الْحَمْدُ لِلَّهِ الَّذِي أَحْيَانَا بَعْدَ مَا أَمَاتَنَا وَإِلَيْهِ النُّشُورُ", ur="تمام تعریفیں اللہ کے لیے جس نے ہمیں مارنے کے بعد زندہ کیا", tip="Neend se uthte hi sab se pehle parhein", audio="", src=""},
  {cat="Sona Uthna", title="Karwat Badalte Waqt", ar="لَا إِلَٰهَ إِلَّا اللَّهُ الْوَاحِدُ الْقَهَّارُ", ur="اللہ کے سوا کوئی معبود نہیں، وہ اکیلا اور غالب ہے", tip="Raat ko neend mein karwat lete waqt", audio="", src=""},
  {cat="Baithna Ghar", title="Majlis Mein Baithne Ki Dua", ar="سُبْحَانَكَ اللَّهُمَّ وَبِحَمْدِكَ", ur="اے اللہ تو پاک ہے اور تیری تعریف کے ساتھ", tip="Kaffaratul Majlis - majlis se uthte waqt bhi parhein", audio="", src=""},
  {cat="Hifazat", title="Sayyid-ul-Istighfar", ar="اللَّهُمَّ أَنْتَ رَبِّي لَا إِلَٰهَ إِلَّا أَنْتَ", ur="اے اللہ تو میرا رب ہے تیرے سوا کوئی معبود نہیں", tip="Sab se afzal istighfar (Sahih Bukhari)", audio="", src=""},
  {cat="Hifazat", title="Durood-e-Ibrahimi", ar="اللَّهُمَّ صَلِّ عَلَى مُحَمَّدٍ وَعَلَى آلِ مُحَمَّدٍ", ur="اے اللہ محمد ﷺ اور ان کی آل پر رحمت نازل فرما", tip="Namaz ke Tashahhud mein aur Juma ke din", audio="", src=""},
  -- Neeche di gayi duas ka audio verify hokar mila hai (TheSufi.com, Arabic+Urdu translation):
  {cat="Subah Shaam", title="Subah Ki Dua (Morning Prayer)", ar="", ur="Subah ki masnoon dua", tip="Fajr ke baad parhein", audio="https://www.thesufi.com/Islamic-Collection/Islamic_Audio_Section/67-Islamic-Masnoon-Dua-Arabic-with-Urdu-Translation-MP3/Dua-and-Supplications-Morning-Prayer.mp3", src="TheSufi.com (Arabic+Urdu)"},
  {cat="Sona Uthna", title="Neend Se Uthne Ki Dua (Audio)", ar="", ur="Neend se uthne ki masnoon dua", tip="Neend se uthte hi parhein", audio="https://www.thesufi.com/Islamic-Collection/Islamic_Audio_Section/67-Islamic-Masnoon-Dua-Arabic-with-Urdu-Translation-MP3/Dua-and-Supplications--8-.mp3", src="TheSufi.com (Arabic+Urdu)"},
  {cat="Sona Uthna", title="Buri Neend/Darawana Khawab Aane Ki Dua", ar="", ur="Bura khawab ya neend ki bechaini ki dua", tip="Darawana khawab ane par parhein", audio="https://www.thesufi.com/Islamic-Collection/Islamic_Audio_Section/67-Islamic-Masnoon-Dua-Arabic-with-Urdu-Translation-MP3/Dua-and-Supplications--7-.mp3", src="TheSufi.com (Arabic+Urdu)"},
  {cat="Namaz", title="Namaz Ke Baad Ki Dua", ar="", ur="Namaz mukammal karne ke baad ki dua", tip="Har farz namaz ke baad", audio="https://www.thesufi.com/Islamic-Collection/Islamic_Audio_Section/67-Islamic-Masnoon-Dua-Arabic-with-Urdu-Translation-MP3/Dua-and-Supplications--15-.mp3", src="TheSufi.com (Arabic+Urdu)"},
  {cat="Roza", title="Sehri Ki Dua", ar="", ur="Roza shuru karne (Sehri) ki niyat wali dua", tip="Sehri ke waqt parhein", audio="https://www.thesufi.com/Islamic-Collection/Islamic_Audio_Section/67-Islamic-Masnoon-Dua-Arabic-with-Urdu-Translation-MP3/Dua-and-Supplications--22-.mp3", src="TheSufi.com (Arabic+Urdu)"},
  {cat="Roza", title="Iftar Ki Dua", ar="", ur="Roza kholte waqt ki dua", tip="Iftar ke waqt parhein", audio="https://www.thesufi.com/Islamic-Collection/Islamic_Audio_Section/67-Islamic-Masnoon-Dua-Arabic-with-Urdu-Translation-MP3/Dua-and-Supplications--23-.mp3", src="TheSufi.com (Arabic+Urdu)"},
  {cat="Safar", title="Safar Shuru Karne Ki Dua (Audio)", ar="", ur="Safar shuru karte waqt ki dua", tip="Rawangi se pehle parhein", audio="https://www.thesufi.com/Islamic-Collection/Islamic_Audio_Section/67-Islamic-Masnoon-Dua-Arabic-with-Urdu-Translation-MP3/Dua-and-Supplications--28-.mp3", src="TheSufi.com (Arabic+Urdu)"},
  {cat="Khaas Mawaqe", title="Dua-e-Haajit", ar="", ur="Zaroorat poori hone ki dua", tip="Kisi khaas zaroorat ke waqt", audio="https://www.thesufi.com/Islamic-Collection/Islamic_Audio_Section/67-Islamic-Masnoon-Dua-Arabic-with-Urdu-Translation-MP3/Dua-and-Supplications--1-.mp3", src="TheSufi.com (Arabic+Urdu)"},
  {cat="Khaas Mawaqe", title="Fot Hone Par Taziyat Ki Dua", ar="", ur="Kisi ki wafat par sabr/taziyat ki dua", tip="Ghum ke waqt aur taziyat karte waqt", audio="https://www.thesufi.com/Islamic-Collection/Islamic_Audio_Section/67-Islamic-Masnoon-Dua-Arabic-with-Urdu-Translation-MP3/Dua-and-Supplications--55-.mp3", src="TheSufi.com (Arabic+Urdu)"},
  {cat="Khaas Mawaqe", title="Kamyabi/Muqable Mein Kamyabi Ki Dua", ar="", ur="Muqable ya mushkil mein kamyabi ki dua", tip="Imtihan ya mushkil kaam se pehle", audio="https://www.thesufi.com/Islamic-Collection/Islamic_Audio_Section/67-Islamic-Masnoon-Dua-Arabic-with-Urdu-Translation-MP3/Dua-and-Supplications--57-.mp3", src="TheSufi.com (Arabic+Urdu)"},
  {cat="Khaas Mawaqe", title="Sabaat Aur Rehmat Ki Dua", ar="", ur="Deen par sabaat (istiqamat) aur rehmat ki dua", tip="Rozmarra ki dua ke tor par", audio="https://www.thesufi.com/Islamic-Collection/Islamic_Audio_Section/67-Islamic-Masnoon-Dua-Arabic-with-Urdu-Translation-MP3/Dua-and-Supplications--58-.mp3", src="TheSufi.com (Arabic+Urdu)"},
  {cat="Khaas Mawaqe", title="Barkat Aur Maghfirat Ki Dua", ar="", ur="Barkat aur bakhshish maangne ki dua", tip="Rozmarra ki dua ke tor par", audio="https://www.thesufi.com/Islamic-Collection/Islamic_Audio_Section/67-Islamic-Masnoon-Dua-Arabic-with-Urdu-Translation-MP3/Dua-and-Supplications--64-.mp3", src="TheSufi.com (Arabic+Urdu)"},
  -- Neeche di gayi duas archive.org "Islamic Dua in Audio" collection se hain
  -- (83 individually-labeled files, verify ki gayi hain):
  {cat="Khaana Peena", title="Pani Peene Ke Baad Ki Dua", ar="", ur="Pani peene ke baad ki masnoon dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-after-drinking-water.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Khaana Peena", title="Dawat Mein Khana Khane Ke Baad Ki Dua", ar="", ur="Kisi ki dawat mein khana khane ke baad ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-after-eating-dawat.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Tahaarat", title="Bathroom Se Nikalne Ki Dua", ar="", ur="Bathroom/toilet se nikalne ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-after-exiting-from-the-toilet.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Mausam", title="Baadal Chatne Ki Dua", ar="", ur="Baadal chatne (khulne) ke waqt ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-after-opening-clouds.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Khaas Mawaqe", title="Qarz Wapis Milne Ki Dua", ar="", ur="Apna qarz wapis milne par shukr ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-after-receive-debts.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Rozmarra", title="Naye Kapre Pehnne Ki Dua", ar="", ur="Naye kapre pehante waqt ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-after-wearing-clothes.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Rozmarra", title="Musafa (Handshake) Ki Dua", ar="", ur="Kisi se hath milate waqt ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-at-the-time-of-handshake.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Rozmarra", title="Jamhai (Ubasi) Aane Ki Dua", ar="", ur="Ubasi/jamhai aane par karne wala amal", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-at-the-time-of-jamahi.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Mausam", title="Chand Grehan Ki Dua", ar="", ur="Chand grehan (lunar eclipse) ke waqt ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-at-the-time-of-lunar-eclipse.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Mausam", title="Barish Ke Waqt Ki Dua (Audio)", ar="", ur="Barish shuru hote waqt ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-at-the-time-of-rain.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Rozmarra", title="Tohfa Milne Ki Dua", ar="", ur="Kisi se tohfa (gift) milne par dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-at-the-time-of-receive-gift.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Mausam", title="Suraj Grehan Ki Dua", ar="", ur="Suraj grehan (solar eclipse) ke waqt ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-at-the-time-of-solar-eclipse.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Mausam", title="Aandhi/Toofan Ki Dua", ar="", ur="Tez aandhi/toofan ke waqt ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-at-the-time-of-storm.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Mausam", title="Suraj Nikalte Waqt Ki Dua", ar="", ur="Subah suraj nikalte waqt ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-at-the-time-of-sunrise.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Mausam", title="Suraj Ghurub Hone Ki Dua", ar="", ur="Shaam ko suraj ghurub hote waqt ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-at-the-time-of-sunset.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Khaana Peena", title="Doodh Peene Se Pehle Ki Dua (Audio)", ar="", ur="Doodh peene se pehle ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-before-drinking-milk.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Khaana Peena", title="Pani Peene Se Pehle Ki Dua (Audio)", ar="", ur="Pani peene se pehle ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-before-drinking-water.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Khaana Peena", title="Khana Khane Se Pehle Ki Dua (Audio)", ar="", ur="Khana shuru karne se pehle ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-before-eating.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Tahaarat", title="Bathroom Jaane Ki Dua", ar="", ur="Bathroom/toilet mein dakhil hone se pehle ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-before-entering-the-toilet.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Sona Uthna", title="Sone Se Pehle Ki Dua (Audio)", ar="", ur="Sone se pehle ki masnoon dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-before-sleeping.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Rozmarra", title="Naya Kaam Shuru Karne Ki Dua", ar="", ur="Koi naya kaam shuru karte waqt ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-before-starting-new-work.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Khaas Mawaqe", title="Maghfirat Maangne Ki Dua", ar="", ur="Allah se maghfirat maangne ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-for-asking-forgiveness.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Baithna Ghar", title="Ghar Mein Dakhil Hone Ki Dua (Audio)", ar="", ur="Ghar mein dakhil hote waqt ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-for-entering-house.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Masjid", title="Masjid Mein Dakhil Hone Ki Dua (Audio)", ar="", ur="Masjid mein dakhil hote waqt ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-for-entering-masjid.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Rozmarra", title="Bazaar Mein Dakhil Hone Ki Dua", ar="", ur="Bazaar/market mein jaate waqt ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-for-entering-the-marketplace.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Masjid", title="Masjid Se Nikalne Ki Dua (Audio)", ar="", ur="Masjid se nikalte waqt ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-for-exiting-masjid.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Rozmarra", title="Shukriya Ada Karne Ki Dua", ar="", ur="Kisi ka shukriya ada karte waqt ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-for-expressing-thanks.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Ramzan", title="Ramzan Ke Pehle Ashre Ki Dua", ar="", ur="Ramzan ke pehle ashre (rehmat) ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-for-first-ashra-of-ramadan.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Khaas Mawaqe", title="Qarz Utarne Ki Dua", ar="", ur="Qarz jaldi utarne ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-for-payment-of-debt.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Rozmarra", title="Surma Lagane Ki Dua", ar="", ur="Aankhon mein surma lagate waqt ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-for-putting-on-surma.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Mausam", title="Barish Ke Liye Dua (Istisqa)", ar="", ur="Barish na ho rahi ho to mangne ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-for-rain-to-come.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Rozmarra", title="Kitab Parhne Ki Dua", ar="", ur="Koi kitab parhna shuru karne ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-for-reading-the-book.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Ramzan", title="Ramzan Ke Dusre Ashre Ki Dua", ar="", ur="Ramzan ke dusre ashre (maghfirat) ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-for-second-ashra-of-ramadan.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Khaas Mawaqe", title="Kisi Ko Museebat Mein Dekh Kar Dua", ar="", ur="Kisi ko museebat/museebat zada dekh kar parhne ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-for-seeing-someone-in-difficulty.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Ramzan", title="Ramzan Ke Teesre Ashre Ki Dua", ar="", ur="Ramzan ke teesre ashre (jahannam se azadi) ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-for-third-ashra-of-ramadan.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Khaas Mawaqe", title="Mushkil/Museebat Ke Waqt Ki Dua", ar="", ur="Kisi mushkil ya museebat ke waqt ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-for-trouble.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Rozmarra", title="Seerhi/Upar Chadhte Waqt Ki Dua", ar="", ur="Upar chadhte (seerhi ya pahar) waqt ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-for-upstairs.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Rozmarra", title="Aaina Dekhne Ki Dua", ar="", ur="Aaine mein apni surat dekhte waqt ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-for-when-looking-in-a-mirror.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Khaas Mawaqe", title="Gussa Aane Par Dua", ar="", ur="Gussa aane par parhne ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-for-when-one-suffers-anger.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Ramzan", title="Qurbani Ki Dua", ar="", ur="Qurbani karte waqt ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-of-qurbani.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Ramzan", title="Shab-e-Qadr Ki Dua", ar="", ur="Shab-e-Qadr mein parhne ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-of-shab-e-qadr.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Rozmarra", title="Cheenk Aane Ki Dua", ar="", ur="Khud ko cheenk aane par parhne ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-of-sneezing.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Ramzan", title="Taraweeh Ki Dua", ar="", ur="Taraweeh ki namaz se mutaliq dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-of-taraweeh.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Rozmarra", title="Kisi Musalman Ko Khush Dekh Kar Dua", ar="", ur="Kisi musalman bhai ko muskurate dekh kar dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-to-be-asked-upon-beholding-a-muslim-smiling.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Jaanwar Ki Awaz", title="Murgh Ki Awaz Sun Kar Dua", ar="", ur="Murgh (rooster) ki awaz sun kar parhne ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-to-be-invoked-upon-hearing-the-crowing-of-a-rooster.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Safar", title="Sawari Par Baithne Ki Dua (Audio)", ar="", ur="Gaadi/sawari par baithte waqt ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-to-be-recited-after-being-settled-onto-a-carriage.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Khaana Peena", title="Khana Saamne Rakhe Jaane Par Dua", ar="", ur="Khana saamne rakha jaye to parhne ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-to-be-recited-when-food-is-placed-before.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Khaas Mawaqe", title="Bimari Mein Parhne Ki Dua", ar="", ur="Bimari ke waqt parhne ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-to-be-recited-while-feeling-sick.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Khaana Peena", title="Har Nawala Khane Ki Dua", ar="", ur="Har luqma/nawala khane par parhne ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-to-eat-every-morsel.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Khaana Peena", title="Pehla Nawala Khane Ki Dua", ar="", ur="Khane ka pehla nawala uthate waqt ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-to-eat-first-morsel.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Khaas Mawaqe", title="Thakan Dur Karne Ki Dua", ar="", ur="Thakan mehsoos hone par parhne ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-to-get-rid-of-tiredness.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Khaas Mawaqe", title="Waswase Se Bachne Ki Dua", ar="", ur="Shaitani waswase se bachne ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-to-get-rid-of-waswas.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Rozmarra", title="Musalman Se Milte Waqt Ki Dua", ar="", ur="Kisi musalman bhai se milte waqt ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-to-meet-with-muslim.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Mausam", title="Garaj (Thunder) Ke Waqt Ki Dua", ar="", ur="Baadal garajne (thunder) ke waqt ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-to-read-at-time-of-thunder.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Chand Sitare", title="Chand Dekhne Ki Dua", ar="", ur="Chand dekhte waqt ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-to-see-moon.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Chand Sitare", title="Sitare Dekhne Ki Dua", ar="", ur="Sitare dekhte waqt ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-to-see-stars.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Masjid", title="Masjid Dekhte Hi Ki Dua", ar="", ur="Masjid nazar aate hi parhne ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-to-see-the-masjid.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Khaana Peena", title="Phal Khane Ki Dua", ar="", ur="Naya phal khane se pehle ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-to-take-fruit.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Jaanwar Ki Awaz", title="Gadhe Ki Awaz Sun Kar Dua", ar="", ur="Gadhe (donkey) ki awaz sun kar parhne ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-upon-hearing-braying-of-a-donkey.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Jaanwar Ki Awaz", title="Kutte Ke Bhonkne Ki Awaz Sun Kar Dua", ar="", ur="Kutte ke bhonkne ki awaz sun kar parhne ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-upon-hearing-the-barking-of-a-dog.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Chand Sitare", title="Naya Chand Dekhne Ki Dua", ar="", ur="Mahine ka naya chand dekhte waqt ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-upon-sighting-the-new-moon.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Baithna Ghar", title="Ghar Se Nikalte Waqt Ki Dua (Audio)", ar="", ur="Ghar se bahar nikalte waqt ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-when-exiting-the-home.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Rozmarra", title="Kisi Ko Cheenkte Sun Kar Dua (Yarhamuk Allah)", ar="", ur="Kisi aur ko cheenkte sun kar jawab dena", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-when-hearing-someone-sneeze.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Chand Sitare", title="Tootay Hue Tare (Shooting Star) Dekhne Ki Dua", ar="", ur="Tootay hue tare ko dekh kar parhne ki dua", tip="", audio="https://archive.org/download/islamic-dua-in-audio/dua-when-seeing-shooting-star.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Hajj", title="Takbeer-e-Tashreeq", ar="", ur="Eid ke ayyam-e-tashreeq mein parhi jane wali takbeer", tip="", audio="https://archive.org/download/islamic-dua-in-audio/takbeer-e-tashreeq.mp3", src="archive.org (Islamic Dua in Audio)"},
  {cat="Hajj", title="Talbiyah", ar="", ur="Hajj/Umrah ke ihram ki talbiyah", tip="", audio="https://archive.org/download/islamic-dua-in-audio/talbiyah.mp3", src="archive.org (Islamic Dua in Audio)"},
  -- NAYA (v2.1): "Rabbana..." - Quran mein maujood 40 duaein (archive.org:
  -- Rabbana-40-Supplications), verified, sab per-dua chhoti aur saaf files
  {cat="Rabbana (Quranic Dua)", title="Allah Never Break His Promise", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/01%20Allah%20never%20break%20his%20promise.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="No Help For Zalimun", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/02%20No%20help%20for%20zalimun.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="Grant Us What You Promised", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/03%20Grant%20us%20what%20You%20promised.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="We Believe", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/04%20We%20believe.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="Provide Us Sustenance", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/05%20Provide%20us%20Sustenance.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="You Are The Best Judge", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/06%20You%20are%20the%20best%20judge.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="Save Us By Your Mercy", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/07%20Save%20us%20by%20Your%20Mercy.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="Nothing Is Hidden From Allah", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/08%20Nothing%20is%20hidden%20from%20Allah.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="We Fear Lest", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/09%20We%20fear%20lest.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="Avert The Torment Of Hell", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/10%20Avert%20the%20Torment%20of%20Hell.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="Leaders Of The Muttaqun", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/11%20Leaders%20of%20the%20Muttaqun.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="Punish Us Not", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/12%20Punish%20us%20not.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="Lay Not On Us A Burden", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/13%20Lay%20not%20on%20us%20a%20Burden.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="Pardon And Grant Us Forgiveness", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/14%20Pardon%20and%20Grant%20us%20Forgiveness.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="Forgive Us Our Sins", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/15%20Forgive%20us%20our%20Sins.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="Victory Over Disbelievers", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/16%20Victory%20over%20Disbelievers.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="Bestow Upon Us Your Mercy", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/17%20Bestow%20upon%20us%20Your%20Mercy.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="Forgive Me And My Parents", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/18%20Forgive%20me%20and%20my%20Parents.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="Grant Us Forgiveness", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/19%20Grant%20us%20Forgiveness.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="Give Us In This World Good", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/20%20Give%20us%20in%20this%20World%20Good.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="Save Us From Fire", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/21%20Save%20us%20from%20Fire.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="Place Us Not With Zalimun", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/22%20Place%20us%20not%20with%20Zalimun.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="Make Them Enter The Paradise", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/23%20Make%20them%20enter%20the%20Paradise.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="Bestow Mercy From Yourself", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/24%20Bestow%20Mercy%20from%20Yourself.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="We Believe, Forgive Us", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/25%20We%20Believe%2C%20Forgive%20us.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="Forgive Us And Our Brethren", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/26%20Forgive%20us%20and%20our%20Brethren.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="Allah Is Full Of Kindness", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/27%20Allah%20is%20Full%20of%20Kindness.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="Make Us Not A Trail", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/28%20Make%20us%20not%20a%20Trail.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="Accept Our Repentance", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/29%20Accesp%20our%20Repentance.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="Let Not Our Hearts Deviate", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/30%20Let%20not%20our%20Hearts%20Deviate.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="We Believe In What You Have Sent", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/31%20We%20believe%20in%20what%20You%20have%20sent.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="Believe In Allah", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/32%20Believe%20in%20Allah.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="Remit Our Evil Deeds", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/33%20Remit%20our%20Evil%20Deeds.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="Forgive Those Who Repent", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/34%20Forgive%20those%20who%20Repent.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="We Turn In Repentance", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/35%20We%20Turn%20in%20Repentance.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="Accept Our Service", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/36%20Accept%20our%20Service.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="Give Us Patience", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/37%20Give%20us%20Patience.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="To Die As Muslim", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/38%20To%20Die%20as%20Muslim.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="Accept My Invocation", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/39%20Accept%20my%20Invocation.mp3", src="archive.org (Rabbana 40 Supplications)"},
  {cat="Rabbana (Quranic Dua)", title="Allah Is Oft-Forgiving", ar="", ur="", tip="", audio="https://archive.org/download/Rabbana-40-Supplications/40%20Allah%20is%20Oft-Forgiving.mp3", src="archive.org (Rabbana 40 Supplications)"},
}
local function getDuaAudioLocal(d) return duaAudioDir .. "dua_" .. slug(d.title) .. ".mp3" end

-- NAYA (v2.1): "Poori Quran (Continuous)" - poori Quran EK hi bari file
-- mein (Urdu Shamshad Ali Khan tarjuma ke sath mixed), do reciters mein
-- se choose kar sakte hain. Surah-wise seek nahi hoti (koi timestamp data
-- nahi hai), sirf continuous play + scrub + offline download.
local fullQuranVoices = {
  {name="Al-Minshawi (Moratal) + Urdu (Shamshad Ali Khan)", url="https://archive.org/download/FullQuranByALMINSHAWIMORAT356856856835635853xedUrduByShamshadAliKhan64kb/full%20-quran-by-__ALMINSHAWI-MORATAL__mixed_urdu-by-Shamshad-%20Ali-%20Khan-64kb.mp3", file="fullquran_minshawi_urdu.mp3"},
  {name="Al-Hosary + Urdu (Shamshad Ali Khan)", url="https://archive.org/download/FullQuranByAlhosaryTeacherWithoutKidsMixedUr356858633568353535686535368duByShamshadAliKhan64kb/full%20-quran-by-__alhosary__teacher__without__kids__mixed_urdu-by-Shamshad-%20Ali-%20Khan-64kb.mp3", file="fullquran_alhosary_urdu.mp3"}
}
local function getFullQuranLocal(v) return duaAudioDir .. v.file end

-- NAYA (v2.1): Hadith - Sahih Bukhari (English), 97 Kitab (Books) ki
-- audio, har Kitab apni file mein (archive.org: sahih-bukhari-english-audio,
-- QNS Academy) - Urdu wala source clean/reliable nahi mila is liye
-- English (jis mein poori 97 Kitab ki saaf list hai) use ki gayi hai.
local HADITH_BASE = "https://archive.org/download/sahih-bukhari-english-audio/"
local hadithBooks = {
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
local function buildHadithUrl(b) return HADITH_BASE .. urlEncodeBytes(b.file) end
local function getHadithLocal(b) return duaAudioDir .. "hadith_bukhari_" .. b.n .. ".mp3" end

-- NAYA (v2.1): Tafseer-e-Quran (Bayan-ul-Quran) by Dr. Israr Ahmad, Urdu -
-- 115 files (1 Introduction + 114 Surahs), archive.org: tafseer-e-quran-urdu
-- - verified. Filenames formula se nahi bantay (spacing/casing quirks
-- asal source mein), is liye har ek verify kar ke likhi gayi hai.
local ISRAR_TAFSEER_BASE = "https://archive.org/download/tafseer-e-quran-urdu/"
local israrTafseerFiles = {
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
local function buildIsrarTafseerUrl(t) return ISRAR_TAFSEER_BASE .. urlEncodeBytes(t.file) end
local function getIsrarTafseerLocal(t) return duaAudioDir .. "tafseer_israr_" .. t.n .. ".mp3" end

--------------------------------------------------
-- BOOKMARKS, PINS, DELETES
--------------------------------------------------
local bookmarksStr = prefs.getString("bookmarks", "")
local bookmarks = {}
if bookmarksStr ~= "" then for s in string.gmatch(bookmarksStr, "([^,]+)") do table.insert(bookmarks, tonumber(s)) end end

local pinnedStr = prefs.getString("pinnedSurahs", "")
local pinned = {}
if pinnedStr ~= "" then for s in string.gmatch(pinnedStr, "([^,]+)") do pinned[tonumber(s)] = true end end

local deletedStr = prefs.getString("deletedSurahs", "")
local deletedSurahs = {}
if deletedStr ~= "" then for s in string.gmatch(deletedStr, "([^,]+)") do deletedSurahs[tonumber(s)] = true end end

local function saveBookmarks() prefs.edit().putString("bookmarks", table.concat(bookmarks, ",")).apply() end
local function savePinned() local arr = {} for k,v in pairs(pinned) do if v then table.insert(arr, k) end end prefs.edit().putString("pinnedSurahs", table.concat(arr, ",")).apply() end
local function saveDeleted() local arr = {} for k,v in pairs(deletedSurahs) do if v then table.insert(arr, k) end end prefs.edit().putString("deletedSurahs", table.concat(arr, ",")).apply() end
-- Persist reciter by NAME (not index) so a reordered live-list can't scramble it
local function saveLastPlayed(s_index, r_index)
  local rName = reciters[r_index] and reciters[r_index].name or ""
  prefs.edit().putInt("lastSurah", s_index).putString("lastReciterName", rName).apply()
  lastPlayedSurah = s_index
  lastPlayedReciter = r_index
end
local function saveActiveTasbeehState() prefs.edit().putInt("activeCount", tasbeehCount).putInt("activeTarget", tasbeehTarget).putInt("activeWazeefa", currentWazeefaIndex).putBoolean("tasbeehBeep", tasbeehBeepEnabled).putBoolean("tasbeehVibrate", tasbeehVibrateEnabled).apply() end

--------------------------------------------------
-- HARDWARE & NOTIFICATION HELPERS
--------------------------------------------------
local function playBeep() pcall(function() local r=import("android.media.RingtoneManager") local uri=r.getDefaultUri(r.TYPE_NOTIFICATION) r.getRingtone(activity,uri).play() end) end
local function doVibrate(ms) pcall(function() activity.getSystemService(Context.VIBRATOR_SERVICE).vibrate(ms) end) end
local function hideKeyboard(view) pcall(function() activity.getSystemService(Context.INPUT_METHOD_SERVICE).hideSoftInputFromWindow(view.getWindowToken(), 0) end) end
local function showPlaybackNotification(title, text) pcall(function() local nm = activity.getSystemService(Context.NOTIFICATION_SERVICE) if Build.VERSION.SDK_INT >= 26 then nm.createNotificationChannel(NotificationChannel("quran_audio_v2", "Quran Playback", NotificationManager.IMPORTANCE_DEFAULT)) end local builder = Notification.Builder(activity) if Build.VERSION.SDK_INT >= 26 then builder = Notification.Builder(activity, "quran_audio_v2") end
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
  if not actOk and not notifActionErrorShown then
    notifActionErrorShown = true
    Toast.makeText(activity, "Notification controls add nahi ho sakay - error: " .. tostring(actErr), 1).show()
  end

  builder.setContentTitle(title).setContentText(text).setSmallIcon(android.R.drawable.ic_media_play).setOngoing(true)
  nm.notify(1, builder.build()) end) end
local function cancelNotification() pcall(function() activity.getSystemService(Context.NOTIFICATION_SERVICE).cancel(1) end) end

--------------------------------------------------
-- PLAYER LOGIC
--------------------------------------------------
local function startSleepTimer()
  targetSleepTime = 0
  if sleepTimerMinutes > 0 and mp and mp.isPlaying() then
    targetSleepTime = os.time() + (sleepTimerMinutes * 60)
  end
end

local function stopPlayer(onDone)
  if updateTask then handler.removeCallbacks(updateTask) end
  targetSleepTime = 0
  -- FIX: stop()/release() ko UI thread par turant call karna kabhi kabhi
  -- (khaas kar jab MediaPlayer abhi "preparing" state mein ho, jaise network
  -- se load ho raha ho) device ko hang/freeze kar sakta hai jo TalkBack tak
  -- crash kar deta hai. Ab yeh background thread par hota hai taake Back
  -- button/navigation kabhi block na ho.
  -- FIX 2: purana player release hone se PEHLE agar naya MediaPlayer bana
  -- kar prepare kiya jaye (dono ek sath, alag threads par), to native audio
  -- system par crash ho sakta hai (CSR/TalkBack tak crash kar deta hai) -
  -- ab onDone callback tabhi chalta hai jab purana player poora release ho
  -- chuka ho, taake naya player uske baad hi banaya jaye, kabhi ek sath nahi.
  local oldMp = mp
  local oldDuaMp = duaMp
  mp = nil
  duaMp = nil
  cancelNotification()
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

-- FIX: kuch external hosts (archive.org, thesufi.com) is device/Android
-- version par MediaPlayer ke seedhe HTTPS streaming se theek se stream nahi
-- ho rahe the - is wajah se "online play" kaam nahi kar raha tha. Aur pehle
-- download ka DownloadManager notification tap hone par Android khud file ko
-- default app (YouTube Music) mein khol deta tha - isi liye download ke baad
-- bhi hamari app ke andar dobara play nahi ho rahi thi.
-- Ab: pehle seedha stream try karta hai; agar fail ho to background mein
-- CHUPKE se (koi clickable notification nahi, VISIBILITY_HIDDEN) download
-- karta hai aur download hote hi khud-ba-khud local file se play karta hai.
-- Replay hamesha kaam karega kyunke yeh function pehle hamesha local cache
-- file check karta hai.
-- urls: ek single URL string, YA fallback ke liye URLs ki table {url1, url2, ...}
local function playReliable(urls, cachePath, label, refreshFn, onComplete)
  local urlList = (type(urls) == "table") and urls or {urls}
  local tryStream -- forward declare so the cached-file branch can fall back to it on async failure

  stopPlayer(function()
  local urlIdx = 1
  tryStream = function()
    local url = urlList[urlIdx]
    Toast.makeText(activity, "Loading: " .. label .. "...", 1).show()
    duaMp = MediaPlayer()
    pcall(function() duaMp.setAudioStreamType(AudioManager.STREAM_MUSIC) end)
    local streamFailed = false
    local dsOk = pcall(function() duaMp.setDataSource(url) end)
    if not dsOk then
      Toast.makeText(activity, "Audio source set nahi ho saka.", 0).show()
      return
    end
    duaMp.setOnErrorListener(MediaPlayer.OnErrorListener{onError=function(p,w,e)
      if streamFailed then return true end
      streamFailed = true
      if urlIdx < #urlList then
        -- agla mirror/link try karo pehle
        urlIdx = urlIdx + 1
        pcall(function() duaMp.release() end)
        tryStream()
        return true
      end
      Toast.makeText(activity, "Online stream nahi hui, ab background mein download karke play karenge...", 1).show()
      local dlOk, dlErr = pcall(function()
        local dm = activity.getSystemService(Context.DOWNLOAD_SERVICE)
        local req = DownloadManager.Request(Uri.parse(url))
        req.setTitle(label)
        -- FIX: VISIBILITY_HIDDEN public folder ke sath SecurityException
        -- deta hai ("Invalid value for visibility: 2") - Surah download
        -- mein yehi bug mila tha, yahan bhi wahi tha.
        req.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
        req.setDestinationUri(Uri.fromFile(File(cachePath)))
        dm.enqueue(req)
      end)
      if not dlOk then
        showErrorDialog("Download Error", dlErr)
        return true
      end
      Thread(Runnable{run=function()
        local tries = 0
        while not File(cachePath).exists() and tries < 60 do
          pcall(function() Thread.sleep(1000) end)
          tries = tries + 1
        end
        handler.post(Runnable{run=function()
          if File(cachePath).exists() then
            playReliable(urlList, cachePath, label, refreshFn, onComplete)
          else
            Toast.makeText(activity, "Download bhi fail ho gaya - internet connection check karein.", 0).show()
          end
        end})
      end}).start()
      return true
    end})
    duaMp.setOnPreparedListener(MediaPlayer.OnPreparedListener{onPrepared=function(p) p.start() Toast.makeText(activity, "Playing: " .. label, 0).show() if refreshFn then refreshFn() end end})
    duaMp.setOnCompletionListener(MediaPlayer.OnCompletionListener{onCompletion=function() if onComplete then onComplete() elseif refreshFn then refreshFn() end end})
    duaMp.prepareAsync()
  end

  if File(cachePath).exists() and File(cachePath).length() >= 1000 then
    local fileSize = File(cachePath).length()
    local ok = pcall(function()
      duaMp = MediaPlayer()
      pcall(function() duaMp.setAudioStreamType(AudioManager.STREAM_MUSIC) end)
      duaMp.setDataSource(cachePath)
      duaMp.setOnErrorListener(MediaPlayer.OnErrorListener{onError=function(p,w,e)
        -- Cached file khud prepare/play hote waqt fail hui (corrupt ho sakti
        -- hai) - ab yeh dead-end nahi hai, online stream try karta hai
        Toast.makeText(activity, "Cached file (size: " .. fileSize .. " bytes) kharab nikli, online try kar rahe hain...", 0).show()
        pcall(function() File(cachePath).delete() end)
        pcall(function() duaMp.release() end)
        duaMp = nil
        tryStream()
        return true
      end})
      duaMp.setOnPreparedListener(MediaPlayer.OnPreparedListener{onPrepared=function(p) p.start() Toast.makeText(activity, "Playing (offline): " .. label, 0).show() if refreshFn then refreshFn() end end})
      duaMp.setOnCompletionListener(MediaPlayer.OnCompletionListener{onCompletion=function() if onComplete then onComplete() elseif refreshFn then refreshFn() end end})
      duaMp.prepareAsync()
    end)
    if ok then return end
    -- setDataSource khud (synchronously) fail hui - cache hata kar stream try karte hain
    pcall(function() if duaMp then duaMp.release() end end)
    duaMp = nil
    pcall(function() File(cachePath).delete() end)
    Toast.makeText(activity, "Cached file mein masla tha (size: " .. fileSize .. " bytes), dobara try kar rahe hain...", 0).show()
  end

  tryStream()
  end)
end

local playerReady = false      -- FIX: true sirf jab mp poori tarah "prepared" ho chuka ho
local playIntentPending = false -- agar user ne prepare hone se PEHLE Play dabaya
local function togglePlayPause()
  if not mp then return end
  if not playerReady then
    -- FIX: "pehli dafa Play na hona" bug - bari (translation wali) files
    -- load hone mein waqt leti hain. Pehle is haalat mein mp.start() seedha
    -- bulaya jata tha, jo abhi-prepare-na-hue player par crash kar ke
    -- chup-chaap (pcall ke andar) fail ho jata tha - button ka text tak
    -- nahi badalta tha. Ab hum sirf "intent" yaad rakhte hain, aur jaise hi
    -- prepare mukammal hoti hai (onPrepared) khud-ba-khud start ho jati hai.
    playIntentPending = true
    pcall(function() if btnPlayPause then btnPlayPause.setText(tr("Loading...")) end end)
    return
  end
  pcall(function()
    if mp.isPlaying() then
      mp.pause() isPaused=true
      if btnPlayPause then btnPlayPause.setText("▶ " .. tr("Play")) end
      targetSleepTime = 0
      if surahNames[currentIndex] then showPlaybackNotification(surahNames[currentIndex], "Reciter: " .. (reciters[currentReciter] and reciters[currentReciter].name or "")) end
    else
      mp.start() isPaused=false
      if btnPlayPause then btnPlayPause.setText("⏸ " .. tr("Pause")) end
      startSleepTimer()
      if surahNames[currentIndex] then showPlaybackNotification(surahNames[currentIndex], "Reciter: " .. (reciters[currentReciter] and reciters[currentReciter].name or "")) end
    end
  end)
end
local function seekForward() if mp and mp.isPlaying() then local n = mp.getCurrentPosition()+(seekSeconds*1000) if n>mp.getDuration() then n=mp.getDuration() end mp.seekTo(n) Toast.makeText(activity,"Forward "..seekSeconds.."s",0).show() end end
local function seekRewind() if mp and mp.isPlaying() then local n = mp.getCurrentPosition()-(seekSeconds*1000) if n<0 then n=0 end mp.seekTo(n) Toast.makeText(activity,"Rewind "..seekSeconds.."s",0).show() end end

local showHome, showSettings, showAbout, showFeedback, showSurahList, showPlayer, showTasbeeh, showBookmarksScreen, showNamesOfAllah, showReadingMode, showDailyDuas, showPara, showParaSurahs, playNextSurah, playPrevSurah, downloadSurah, confirmDelete

--------------------------------------------------
-- UI IMPLEMENTATIONS
--------------------------------------------------

-- Bottom tab bar (Home / Quran / Duas / More) - jaise system nav bar mein hota hai
local function bottomTabs(activeTab)
  local function tabColor(tab) return (activeTab == tab) and appColorStr or "#00000000" end
  local function tabTextColor(tab) return (activeTab == tab) and -1 or -12303292 end
  return {LinearLayout, orientation=0, layout_width=-1, backgroundColor="#1A000000",
    {Button, text="Home", textSize="13sp", layout_weight=1, backgroundColor=tabColor("home"), textColor=tabTextColor("home"), contentDescription="Home tab", onClick=function() showHome() end},
    {Button, text="Quran", textSize="13sp", layout_weight=1, backgroundColor=tabColor("quran"), textColor=tabTextColor("quran"), contentDescription="Quran tab", onClick=function() showSurahList() end},
    {Button, text="Duas", textSize="13sp", layout_weight=1, backgroundColor=tabColor("duas"), textColor=tabTextColor("duas"), contentDescription="Duas tab", onClick=function() showDailyDuas() end},
    {Button, text="More", textSize="13sp", layout_weight=1, backgroundColor=tabColor("more"), textColor=tabTextColor("more"), contentDescription="More tab", onClick=function() showMore() end}
  }
end

-- More section ke andar (More aur uske sub-screens) alag tabs dikhte hain -
-- purani Home/Quran/Duas/More tabs yahan hide ho jati hain, jaisa maanga gaya
local function moreSubTabs(activeTab)
  local function tabColor(tab) return (activeTab == tab) and appColorStr or "#00000000" end
  local function tabTextColor(tab) return (activeTab == tab) and -1 or -12303292 end
  -- FIX (v2.1): pehle sirf 5 items yahan the (baaki More screen mein bade
  -- button ke tor par alag se thay) - ab har cheez jo More mein hai wo
  -- yahan bhi tab ke tor par hai, taake har jagah se ek hi tap mein
  -- switch ho sake. Zyada items fit karne ke liye horizontally scroll hoti hai.
  return {HorizontalScrollView, layout_width=-1, backgroundColor="#1A000000",
    {LinearLayout, orientation=0, layout_width="wrap_content",
      {Button, text="Para", textSize="12sp", layout_width="72dp", backgroundColor=tabColor("para"), textColor=tabTextColor("para"), contentDescription="30 Para tab", onClick=function() showPara() end},
      {Button, text="Tasbeeh", textSize="12sp", layout_width="72dp", backgroundColor=tabColor("tasbeeh"), textColor=tabTextColor("tasbeeh"), contentDescription="Digital Tasbeeh tab", onClick=function() showTasbeeh() end},
      {Button, text="Bookmarks", textSize="12sp", layout_width="72dp", backgroundColor=tabColor("bookmarks"), textColor=tabTextColor("bookmarks"), contentDescription="Bookmarks tab", onClick=function() showBookmarksScreen() end},
      {Button, text="Names", textSize="12sp", layout_width="72dp", backgroundColor=tabColor("names"), textColor=tabTextColor("names"), contentDescription="99 Names tab", onClick=function() showNamesOfAllah() end},
      {Button, text="Prophet Names", textSize="12sp", layout_width="72dp", backgroundColor=tabColor("asmanabi"), textColor=tabTextColor("asmanabi"), contentDescription="Blessed Names tab", onClick=function() showAsmaNabi() end},
      {Button, text="Full Quran", textSize="12sp", layout_width="72dp", backgroundColor=tabColor("fullquran"), textColor=tabTextColor("fullquran"), contentDescription="Poori Quran Continuous tab", onClick=function() showFullQuranScreen() end},
      {Button, text="Hadith", textSize="12sp", layout_width="72dp", backgroundColor=tabColor("hadith"), textColor=tabTextColor("hadith"), contentDescription="Hadith tab", onClick=function() showHadithScreen() end},
      {Button, text="Tafseer 2", textSize="12sp", layout_width="72dp", backgroundColor=tabColor("israr"), textColor=tabTextColor("israr"), contentDescription="Tafseer Israr Ahmad tab", onClick=function() showIsrarTafseerScreen() end},
      {Button, text="Menu", textSize="12sp", layout_width="72dp", backgroundColor=tabColor("menu"), textColor=tabTextColor("menu"), contentDescription="Menu tab", onClick=function() showSettings() end},
      {Button, text="Home", textSize="12sp", layout_width="72dp", backgroundColor=tabColor("home"), textColor=tabTextColor("home"), contentDescription="Back to Home tab", onClick=function() showHome() end}
    }
  }
end

local duaPlayerIndex = 1
local audioDuasCache = {}
local function buildAudioDuasList()
  audioDuasCache = {}
  for _, d in ipairs(dailyDuas) do if d.audio ~= "" then table.insert(audioDuasCache, d) end end
  return audioDuasCache
end

-- Universal search index (Surahs + Reciters + Duas) - jaise Advance Media
-- Player mein live search bar hota hai, waisa hi Home par ek hi search bar
local function buildSearchIndex()
  local idx = {}
  for i, name in ipairs(surahNames) do
    -- FIX (v2.1): pehle sirf "Play Surah" hota tha - ab tap karne par
    -- Play/Ayat-ba-Ayat/Ruku/Word-by-Word mein se choose kar sakte hain
    table.insert(idx, {label="Surah: " .. name, action=function()
      AlertDialog.Builder(activity).setTitle(name).setItems({"Play Surah", "Ayat-ba-Ayat Mode", "Ruku Mode", "Word-by-Word (Hifz)"}, {onClick=function(d, w)
        if w == 0 then showPlayer(i)
        elseif w == 1 then showAyahByAyah(i)
        elseif w == 2 then showRukuMode(i)
        elseif w == 3 then showWbwStartDialog(i) end
      end}).show()
    end})
  end
  -- NAYA (v2.1): 30 Para bhi search mein - tap karne par turant play hota hai
  for i, n in ipairs(paraNames) do
    table.insert(idx, {label="Para " .. i .. ": " .. n, action=function()
      showParaScreen()
      playPara(i)
    end})
  end
  -- NAYA (v2.1): Tarjuma (translation) bhi search se select ho sakta hai
  for _, lang in ipairs({"Off", "Urdu", "Hindi", "Punjabi", "English"}) do
    table.insert(idx, {label="Tarjuma: " .. lang, action=function()
      saveTranslationMode(lang)
      Toast.makeText(activity, "Tarjuma set to " .. lang, 1).show()
      showSurahList()
    end})
  end
  for i, r in ipairs(reciters) do
    local rName = r.name
    table.insert(idx, {label="Reciter: " .. rName, action=function()
      currentReciter = i
      Toast.makeText(activity, "Reciter set to " .. rName .. " - ab Surah select karein", 1).show()
      showSurahList()
    end})
  end
  for _, d in ipairs(dailyDuas) do
    if d.audio ~= "" then
      table.insert(idx, {label="Dua (Audio): " .. d.title, action=function()
        buildAudioDuasList()
        for ai, ad in ipairs(audioDuasCache) do if ad == d then showDuaPlayer(ai) return end end
      end})
    else
      table.insert(idx, {label="Dua (Text): " .. d.title, action=function()
        AlertDialog.Builder(activity).setTitle(d.title).setMessage(d.ar .. "\n\n" .. d.ur).setPositiveButton("OK", nil).show()
      end})
    end
  end
  return idx
end

-- NAYA (v2.1): "Surah-name Ayat-number" ya "Surah-number Ayat-number" jaisi
-- query (e.g. "Baqarah 255", "2 255") ko pehchan kar seedha us Ayat par le
-- jaane wala search result banata hai
local function buildAyahSearchResult(query)
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


-- 1. HOME
function showHome()
  screen = "home"
  stopPlayer()
  activity.getWindow().clearFlags(128)
  local bgColor, textColor = getThemeColors()
  local spot = pickSpotlight()
  local searchIndex = nil -- built lazily on first keystroke

  -- FIX (v2.1): agar aakhri prayer-time fetch AAJ ki tareekh ki nahi hai
  -- (matlab purana din, ya kabhi fetch hi nahi hui), to khud-ba-khud
  -- background mein dobara fetch ho jati hai - bina button dabaye
  if lastPrayerFetchDate ~= todayDateString() and savedCity ~= "" and savedCountry ~= "" then
    fetchPrayerTimes(savedCity, savedCountry, function(ok)
      if ok and screen == "home" then showHome() end
    end)
  end

  activity.setContentView(loadlayout{
    LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor, focusable=true, focusableInTouchMode=true,
    {TextView, text="Quran Majeed v2.1", textSize="24sp", typeface=Typeface.DEFAULT_BOLD, gravity="center", padding="10dp", textColor=appColorStr, contentDescription="Quran Majeed, version 2 point 1"},
    {LinearLayout, orientation=0, layout_width=-1, padding="10dp", gravity="center_vertical",
      {EditText, id="etHomeSearch", hint="Search Surah, Reciter, or Dua...", layout_weight=1, singleLine=true, textColor=textColor, hintTextColor="#888888"},
      {Button, id="btnHomeSearch", text="Search", textSize="13sp", layout_marginLeft="5dp", backgroundColor=appColorStr, textColor=-1, contentDescription="Search"}
    },
    {TextView, id="txtHomeSearchStatus", text="", textSize="11sp", textColor="#777777", padding="4dp"},
    {ListView, id="homeSearchResults", layout_width=-1, layout_height="260dp"},
    {ScrollView, id="homeScroll", layout_width=-1, layout_height=0, layout_weight=1,
    {LinearLayout, orientation=1, gravity="center_horizontal", padding="20dp", layout_width=-1, layout_height=-2,

      {LinearLayout, orientation=1, layout_width=-1, padding="15dp", layout_marginBottom="15dp", backgroundColor="#1A000000",
        -- NAYA (v2.1): Aaj ki Gregorian date + Islamic (Hijri) date + Battery
        {LinearLayout, orientation=0, layout_width=-1, gravity="center_vertical", layout_marginBottom="6dp",
          {TextView, text=os.date("%d %B %Y (%A)"), textSize="12sp", textColor=textColor, layout_weight=1},
          {TextView, text="🔋 " .. (currentBatteryPercent() >= 0 and (currentBatteryPercent() .. "%") or "?"), textSize="12sp", textColor=textColor}
        },
        {TextView, text=savedHijriDate, textSize="14sp", typeface=Typeface.DEFAULT_BOLD, textColor=appColorStr, layout_marginBottom="10dp", gravity="center"},
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
                fetchPrayerTimes(c, cntry, function(ok)
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
        {LinearLayout, orientation=0, layout_width=-1, gravity="center", layout_marginBottom="10dp",
          {TextView, text="Fajr\n"..prayerFajr, textSize="14sp", textColor=textColor, layout_weight=1, gravity="center"},
          {TextView, text="Dhuhr\n"..prayerDhuhr, textSize="14sp", textColor=textColor, layout_weight=1, gravity="center"},
          {TextView, text="Asr\n"..prayerAsr, textSize="14sp", textColor=textColor, layout_weight=1, gravity="center"},
          {TextView, text="Maghrib\n"..prayerMaghrib, textSize="14sp", textColor=textColor, layout_weight=1, gravity="center"},
          {TextView, text="Isha\n"..prayerIsha, textSize="14sp", textColor=textColor, layout_weight=1, gravity="center"}
        },
        {TextView, text="Tahajjud Time: " .. calcTahajjud(prayerMaghrib, prayerFajr), textSize="14sp", typeface=Typeface.DEFAULT_BOLD, textColor="#8E24AA", gravity="center"}
      }
    }},
    bottomTabs("home")
  })
  applyWallpaper(mainLayout, bgColor)

  etHomeSearch.clearFocus()
  pcall(function() mainLayout.requestFocus() end)
  hideKeyboard(etHomeSearch)
  handler.postDelayed(function()
    pcall(function() etHomeSearch.clearFocus() mainLayout.requestFocus() hideKeyboard(etHomeSearch) end)
  end, 200)

  local function runHomeSearch()
    local q = tostring(etHomeSearch.getText()):lower()
    if q == "" then
      homeSearchResults.setAdapter(ArrayAdapter(activity, android.R.layout.simple_list_item_1, {}))
      pcall(function() txtHomeSearchStatus.setText("") end)
    else
      if not searchIndex then searchIndex = buildSearchIndex() end
      local matches = {}
      local labels = {}
      -- NAYA (v2.1): "Surah Ayat-number" jaisi query ho to seedha us Ayat
      -- ka result sab se upar dikhta hai
      local ayahResult = buildAyahSearchResult(q)
      if ayahResult then
        table.insert(matches, ayahResult)
        table.insert(labels, ayahResult.label)
      end
      for _, item in ipairs(searchIndex) do
        if item.label:lower():find(q, 1, true) then
          table.insert(matches, item)
          table.insert(labels, item.label)
          if #matches >= 100 then break end
        end
      end
      pcall(function() txtHomeSearchStatus.setText(#matches .. " result(s) - tap one to play/select it") end)
      homeSearchResults.setAdapter(ArrayAdapter(activity, android.R.layout.simple_list_item_1, labels))
      homeSearchResults.onItemClick = function(l, v, p, i)
        hideKeyboard(etHomeSearch)
        if matches[i+1] then matches[i+1].action() end
      end
    end
  end

  etHomeSearch.addTextChangedListener(TextWatcher{onTextChanged=function(c) runHomeSearch() end})
  btnHomeSearch.onClick = function() hideKeyboard(etHomeSearch) runHomeSearch() end
end

-- DAILY MASNOON DUAS SCREEN (Audio Duas alag, Text Duas alag - TalkBack labels ke saath)
local function playDuaAtIndex(idx, refreshFn)
  local list = audioDuasCache
  if idx < 1 or idx > #list then return end
  duaPlayerIndex = idx
  local d = list[idx]
  playReliable(d.audio, getDuaAudioLocal(d), d.title, refreshFn, function()
    if idx < #list then playDuaAtIndex(idx+1, refreshFn) elseif refreshFn then refreshFn() end
  end)
end

-- DUA PLAYER (Surah player jaisa poora screen: Prev/Rewind/Play-Pause/Forward/Next/Download/Back)
function showDuaPlayer(idx)
  screen = "duaplayer"
  local list = audioDuasCache
  if idx < 1 or idx > #list then return end
  duaPlayerIndex = idx
  local d = list[idx]
  local localPath = getDuaAudioLocal(d)
  local isDownloaded = File(localPath).exists()
  local bgColor, textColor = getThemeColors()

  activity.setContentView(loadlayout{
    LinearLayout, id="mainLayout", orientation=1, padding="20dp", layout_width=-1, layout_height=-1, gravity="center", backgroundColor=bgColor,
    {TextView, text=(isDownloaded and "Offline Mode" or "Online Stream") .. " - " .. idx .. "/" .. #list, textSize="14sp", layout_marginBottom="10dp", textColor=appColorStr},
    {TextView, text=d.title, textSize="24sp", typeface=Typeface.DEFAULT_BOLD, layout_marginBottom="10dp", textColor=appColorStr, gravity="center", contentDescription=d.title},
    {TextView, text=d.ur, textSize="15sp", layout_marginBottom="10dp", textColor=textColor, gravity="center"},
    {TextView, text="💡 " .. d.tip, textSize="12sp", textColor="#777777", layout_marginBottom="20dp", gravity="center"},

    {SeekBar, id="skBar", layout_width=-1, layout_marginBottom="20dp"},
    {LinearLayout, orientation=0, gravity="center", layout_width=-1,
      {Button, text="⏮", textSize="14sp", layout_weight=1, layout_margin="2dp", contentDescription="Previous", onClick=function() if duaPlayerIndex>1 then showDuaPlayer(duaPlayerIndex-1) end end},
      {Button, text="⏪ 10s", textSize="16sp", layout_weight=1, layout_margin="2dp", contentDescription="Rewind 10 seconds", onClick=function() if duaMp and duaMp.isPlaying() then local n=duaMp.getCurrentPosition()-10000 if n<0 then n=0 end duaMp.seekTo(n) end end},
      {Button, id="btnDuaPlayPause", text="⏸ " .. tr("Pause"), textSize="16sp", typeface=Typeface.DEFAULT_BOLD, layout_weight=1.5, layout_margin="2dp", contentDescription="Play or Pause", onClick=function()
        if duaMp then pcall(function() if duaMp.isPlaying() then duaMp.pause() btnDuaPlayPause.setText("▶ " .. tr("Play")) else duaMp.start() btnDuaPlayPause.setText("⏸ " .. tr("Pause")) end end) end
      end},
      {Button, text="10s ⏩", textSize="16sp", layout_weight=1, layout_margin="2dp", contentDescription="Fast Forward 10 seconds", onClick=function() if duaMp and duaMp.isPlaying() then local n=duaMp.getCurrentPosition()+10000 duaMp.seekTo(n) end end},
      {Button, text="⏭", textSize="14sp", layout_weight=1, layout_margin="2dp", contentDescription="Next", onClick=function() if duaPlayerIndex<#list then showDuaPlayer(duaPlayerIndex+1) end end}
    },
    {Button, id="btnDuaDownload", text=isDownloaded and "🗑 Delete Offline" or "⬇️ Download", textSize="14sp", layout_width=-1, layout_marginTop="20dp", backgroundColor=isDownloaded and "#C62828" or "#1976D2", textColor=-1, contentDescription=isDownloaded and "Delete Offline Copy" or "Download"},
    {LinearLayout, orientation=0, gravity="center", layout_marginTop="30dp", layout_width=-1,
      {Button, text=tr("Back"), layout_weight=1, layout_marginRight="10dp", contentDescription="Back to duas list", onClick=function() showDailyDuas() end},
      {Button, text="Exit App", layout_weight=1, backgroundColor="#C62828", textColor=-1, onClick=function() activity.finish() end}
    }
  })
  applyWallpaper(mainLayout, bgColor)

  btnDuaDownload.onClick = function()
    if File(localPath).exists() then
      confirmDelete(localPath, function() showDuaPlayer(duaPlayerIndex) end)
    else
      -- FIX: pehle pcall ka result check hi nahi hota tha, is liye agar
      -- DownloadManager fail hota (VISIBILITY_HIDDEN wala wahi SecurityException
      -- jo Surah download mein tha - yahan bhi tha), to error chup-chaap
      -- nikal jata tha aur "Download shuru..." Toast phir bhi dikh jata
      -- tha, phir 60 second tak kuch na hone par "hang" jaisa lagta tha.
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
      Toast.makeText(activity, "Download shuru...", 1).show()
      Thread(Runnable{run=function()
        local tries = 0
        while not File(localPath).exists() and tries < 60 do pcall(function() Thread.sleep(1000) end) tries = tries + 1 end
        handler.post(Runnable{run=function() if screen == "duaplayer" and duaPlayerIndex == idx then showDuaPlayer(idx) end end})
      end}).start()
    end
  end

  playReliable(d.audio, localPath, d.title, nil, function()
    if btnDuaPlayPause then btnDuaPlayPause.setText("▶ " .. tr("Play")) end
    if duaPlayerIndex < #list then showDuaPlayer(duaPlayerIndex+1) end
  end)
  updateTask = Runnable({run = function()
    if duaMp then pcall(function() if duaMp.isPlaying() then skBar.setMax(duaMp.getDuration()) skBar.setProgress(duaMp.getCurrentPosition()) end end) end
    handler.postDelayed(updateTask, 1000)
  end})
  handler.post(updateTask)
  skBar.setOnSeekBarChangeListener(SeekBar.OnSeekBarChangeListener{onProgressChanged=function(s, p, f) if f and duaMp then pcall(function() duaMp.seekTo(p) end) end end})
end

function showDailyDuas()
  screen = "dailyduas"
  stopPlayer()
  local bgColor, textColor = getThemeColors()
  local list = buildAudioDuasList()

  local textDuas = {}
  for _, d in ipairs(dailyDuas) do if d.audio == "" then table.insert(textDuas, d) end end

  -- ===== AUDIO DUAS rows (Quran Majeed ki surah-list jaisi - sirf tap karein), category-wise grouped =====
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

  -- ===== TEXT-ONLY DUAS rows (alag category, sirf text, audio nahi) =====
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
        {TextView, text="💡 " .. d.tip, textSize="11sp", textColor="#777777", layout_marginTop="4dp"}
      })
    end
  end

  local content = {LinearLayout, orientation=1, layout_width=-1, layout_height=-2}
  for _, r in ipairs(audioRows) do table.insert(content, r) end
  for _, r in ipairs(textRows) do table.insert(content, r) end

  activity.setContentView(loadlayout{
    LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor,
    {LinearLayout, orientation=0, padding="10dp", backgroundColor="#00695C", layout_width=-1, gravity="center_vertical",
      {Button, text=tr("Back"), onClick=function() showHome() end},
      {TextView, text=tr("Daily Masnoon Duas"), textSize="16sp", typeface=Typeface.DEFAULT_BOLD, layout_marginLeft="10dp", textColor=-1}
    },
    {LinearLayout, orientation=0, layout_width=-1, padding="8dp",
      {Button, text="▶️ Full Audio (Vol 1: Hisnul Muslim CD1)", textSize="11sp", layout_weight=1, layout_marginRight="4dp", backgroundColor="#00897B", textColor=-1, contentDescription="Play full Hisnul Muslim recording, volume 1", onClick=function()
        playReliable("https://archive.org/download/HisnulMuslimAudio/CD%201.mp3", duaAudioDir .. "hisnul_muslim_vol1.mp3", "Hisnul Muslim Vol 1", nil, nil)
      end},
      {Button, text="▶️ Full Audio (Vol 2: Hisnul Muslim CD2)", textSize="11sp", layout_weight=1, backgroundColor="#00897B", textColor=-1, contentDescription="Play full Hisnul Muslim recording, volume 2", onClick=function()
        playReliable("https://archive.org/download/HisnulMuslimAudio/CD%202.mp3", duaAudioDir .. "hisnul_muslim_vol2.mp3", "Hisnul Muslim Vol 2", nil, nil)
      end}
    },
    {TextView, text="⚠️ Vol 1/Vol 2 mein KAUN SI dua kis waqt aati hai iski official track-list kahin published nahi hai (yeh sirf 2 lambi recordings hain, alag-alag tracks nahi) - is liye neeche 'Audio Duas' list mein har dua alag se individually verified hai, wahi use karein agar specific dua sunni ho.", textSize="10sp", textColor="#C62828", padding="8dp"},
    {ScrollView, layout_width=-1, layout_height=0, layout_weight=1, content},
    bottomTabs("duas")
  })
  applyWallpaper(mainLayout, bgColor)
end

-- 30 PARA SCREEN
function showPara()
  screen = "para"
  stopPlayer()
  local bgColor, textColor = getThemeColors()
  local items = {}
  for i, n in ipairs(paraNames) do table.insert(items, n) end

  activity.setContentView(loadlayout{
    LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor,
    {LinearLayout, orientation=0, padding="10dp", backgroundColor="#2E7D32", layout_width=-1, gravity="center_vertical",
      {Button, text=tr("Back"), backgroundColor="#1B5E20", textColor=-1, onClick=function() showMore() end},
      {TextView, text="30 Para (Juz-wise)", textSize="16sp", typeface=Typeface.DEFAULT_BOLD, layout_marginLeft="10dp", textColor=-1}
    },
    {TextView, text="Har Para tap karein - us Juz ki Surahon ki list khulegi (play/download).", textSize="11sp", padding="8dp", textColor=textColor},
    {ListView, id="paraList", layout_width=-1, layout_height=-1}
  })
  applyWallpaper(mainLayout, bgColor)
  paraList.setAdapter(ArrayAdapter(activity, android.R.layout.simple_list_item_1, items))
  paraList.onItemClick = function(l, v, p, i) showParaSurahs(i+1) end
end

function showParaSurahs(paraNum)
  screen = "parasurahs"
  local bgColor, textColor = getThemeColors()
  local startS = paraSurahStart[paraNum]
  local endS = (paraNum < 30) and paraSurahStart[paraNum+1] or 114
  local list = {}
  for s = startS, endS do table.insert(list, s) end
  if #list == 0 then list = {startS} end

  local names = {}
  for _, s in ipairs(list) do table.insert(names, surahNames[s]) end

  activity.setContentView(loadlayout{
    LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor,
    {LinearLayout, orientation=0, padding="10dp", backgroundColor="#2E7D32", layout_width=-1, gravity="center_vertical",
      {Button, text=tr("Back"), backgroundColor="#1B5E20", textColor=-1, onClick=function() showPara() end},
      {TextView, text="Para " .. paraNum, textSize="16sp", typeface=Typeface.DEFAULT_BOLD, layout_marginLeft="10dp", textColor=-1}
    },
    {ListView, id="psList", layout_width=-1, layout_height=-1}
  })
  applyWallpaper(mainLayout, bgColor)
  psList.setAdapter(ArrayAdapter(activity, android.R.layout.simple_list_item_1, names))
  psList.onItemClick = function(l, v, p, i) showPlayer(list[i+1]) end
end

-- 99 NAMES OF ALLAH
function showNamesOfAllah()
  screen = "names"
  local bgColor, textColor = getThemeColors()

  local listLayout = {LinearLayout, orientation=1, layout_width=-1, layout_height=-2, padding="15dp"}

  for i, name in ipairs(asmaUlHusna) do
    table.insert(listLayout, {
      LinearLayout, orientation=1, layout_width=-1, layout_marginBottom="15dp", padding="15dp", backgroundColor="#1A000000",
      {TextView, text=tostring(i) .. ". " .. name.ar, textSize="28sp", typeface=Typeface.DEFAULT_BOLD, textColor=appColorStr, gravity="right"},
      {TextView, text=name.ro, textSize="18sp", textColor=textColor, gravity="center_horizontal", layout_marginTop="5dp"},
      {TextView, text=name.ur, textSize="16sp", textColor=textColor, gravity="right", layout_marginTop="5dp"}
    })
  end

  local namesAudioUrls = {
    "https://archive.org/download/99-names-of-allah-asma-ul-husna/99%20names%20of%20Allah%20%20Asma%20Ul%20husna.mp3",
    "https://archive.org/download/AsmaulHusnaMP3/Asmaul%20Husna%20dan%20Artinya%20Asmaul%20Husna%20Mp3%20Asmaul%20Husna%20Beserta%20Artinya%2099%20Asmaul%20Husna%20Asma%20Ul%20Husna%2099%20Nama%20Allah%20TVRI%20Nasional%20Asma%20Ul%20Husna%20TV3%20Dzikir%20Ary%20Ginanjar%20Agustian%20Names%20of%20Allah%20sifat-sifat%20Allah%20pengertian%20asmaul%20husna.mp3",
    "https://archive.org/download/asma-ul-husna-99-names-of-allah/Asma_ul_Husna.mp3"
  }
  local namesLocalPath = duaAudioDir .. "asma_ul_husna_full.mp3"
  local namesDownloaded = File(namesLocalPath).exists()

  activity.setContentView(loadlayout{
    LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor,
    {LinearLayout, orientation=0, padding="10dp", backgroundColor=appColorStr, layout_width=-1, gravity="center_vertical",
      {Button, text=tr("Back"), onClick=function() showMore() end},
      {TextView, text=tr("99 Names of Allah"), textSize="18sp", typeface=Typeface.DEFAULT_BOLD, layout_marginLeft="10dp", textColor=-1}
    },
    {LinearLayout, orientation=0, layout_width=-1, layout_margin="10dp",
      -- FIX: pehle yeh sirf ek "Play" button tha, dobara click karne par
      -- audio hamesha shuru se dobara chalti thi (Pause kabhi hota hi
      -- nahi tha). Ab showDuaPlayer jaisa hi asal Play/Pause toggle hai.
      {Button, id="btnNamesPlayPause", text="▶️ Play Full Audio", textSize="13sp", layout_weight=1, layout_marginRight="4dp", backgroundColor="#8E24AA", textColor=-1},
      -- NAYA: ab offline ke liye download bhi ho sakta hai
      {Button, id="btnNamesDownload", text=namesDownloaded and "🗑 Delete Offline" or "⬇️ Download", textSize="13sp", layout_weight=1, backgroundColor=namesDownloaded and "#C62828" or "#1976D2", textColor=-1}
    },
    {ScrollView, layout_width=-1, layout_height=-1,
      listLayout
    }
  })
  applyWallpaper(mainLayout, bgColor)

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
      playReliable(namesAudioUrls, namesLocalPath, "99 Names of Allah - Full Audio", nil, function()
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

-- BLESSED NAMES OF PROPHET MUHAMMAD (PEACE BE UPON HIM)
function showAsmaNabi()
  screen = "asmanabi"
  local bgColor, textColor = getThemeColors()

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
      {Button, text=tr("Back"), contentDescription="Back to More", onClick=function() showMore() end},
      {TextView, text="Blessed Names of Prophet Muhammad", textSize="16sp", typeface=Typeface.DEFAULT_BOLD, layout_marginLeft="10dp", textColor=-1}
    },
    {ScrollView, layout_width=-1, layout_height=-1,
      listLayout2
    }
  })
  applyWallpaper(mainLayout, bgColor)
end

-- MORE (hub screen for everything not in Home/Quran/Duas tabs)
-- PROGRESS TRACKER (jo Surah pura sun li, aur Ayat-ba-Ayat mein kahan tak
-- pahunche - qari sahab ke liye bachon ki progress dekhna asaan)
function showProgressTracker()
  screen = "progresstracker"
  local bgColor, textColor = getThemeColors()

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
      {Button, text=tr("Back"), onClick=function() showMore() end},
      {TextView, text="Progress Tracker", textSize="16sp", typeface=Typeface.DEFAULT_BOLD, layout_marginLeft="10dp", textColor=-1}
    },
    {TextView, text=completedCount .. " / 114 Surah completed", textSize="13sp", typeface=Typeface.DEFAULT_BOLD, textColor=textColor, padding="10dp"},
    {ScrollView, layout_width=-1, layout_height=-1, content}
  })
  applyWallpaper(mainLayout, bgColor)
end

-- STORAGE MANAGER (kitni MB downloads ho chuki hain, aur sab clear karne ka option)
function showStorageManager()
  screen = "storagemanager"
  local bgColor, textColor = getThemeColors()

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
      {Button, text=tr("Back"), onClick=function() showMore() end},
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
  applyWallpaper(mainLayout, bgColor)
end

-- POORI QURAN (CONTINUOUS) - voice select list
function showFullQuranScreen()
  screen = "fullquranlist"
  stopPlayer()
  local bgColor, textColor = getThemeColors()
  local names = {}
  for i, v in ipairs(fullQuranVoices) do table.insert(names, v.name) end

  activity.setContentView(loadlayout{
    LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor,
    {LinearLayout, orientation=0, padding="10dp", backgroundColor="#3E2723", layout_width=-1, gravity="center_vertical",
      {Button, text=tr("Back"), onClick=function() showMore() end},
      {TextView, text="Poori Quran (Continuous)", textSize="16sp", typeface=Typeface.DEFAULT_BOLD, layout_marginLeft="10dp", textColor=-1}
    },
    {TextView, text="Yeh EK hi bari (kai ghante lambi) file hai - Surah-wise seek nahi hoti, sirf continuous sunein ya scrub karein. Reciter select karein:", textSize="12sp", textColor="#C62828", padding="10dp"},
    {ListView, id="fqList", layout_width=-1, layout_height=0, layout_weight=1}
  })
  applyWallpaper(mainLayout, bgColor)
  fqList.setAdapter(ArrayAdapter(activity, android.R.layout.simple_list_item_1, names))
  fqList.onItemClick = function(l, v, p, i) showFullQuranPlayer(i + 1) end
end

-- POORI QURAN (CONTINUOUS) - player
function showFullQuranPlayer(voiceIdx)
  screen = "fullquranplayer"
  local voice = fullQuranVoices[voiceIdx]
  local localPath = getFullQuranLocal(voice)
  local isDownloaded = File(localPath).exists()
  local bgColor, textColor = getThemeColors()

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
    {Button, text=tr("Back"), layout_width=-1, layout_marginTop="20dp", onClick=function() showFullQuranScreen() end}
  })
  applyWallpaper(mainLayout, bgColor)

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
      playReliable(voice.url, localPath, voice.name, nil, nil)
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

-- HADITH (Sahih Bukhari, English) - book list
function showHadithScreen()
  screen = "hadithlist"
  stopPlayer()
  local bgColor, textColor = getThemeColors()
  local names = {}
  for _, b in ipairs(hadithBooks) do table.insert(names, "Book " .. b.n .. ": " .. b.title) end

  activity.setContentView(loadlayout{
    LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor,
    {LinearLayout, orientation=0, padding="10dp", backgroundColor="#4E342E", layout_width=-1, gravity="center_vertical",
      {Button, text=tr("Back"), onClick=function() showMore() end},
      {TextView, text="Sahih Bukhari (English)", textSize="16sp", typeface=Typeface.DEFAULT_BOLD, layout_marginLeft="10dp", textColor=-1}
    },
    {TextView, text="97 Kitab (Books) - koi bhi select karein", textSize="12sp", textColor="#777777", padding="8dp"},
    {ListView, id="hadithList", layout_width=-1, layout_height=0, layout_weight=1}
  })
  applyWallpaper(mainLayout, bgColor)
  hadithList.setAdapter(ArrayAdapter(activity, android.R.layout.simple_list_item_1, names))
  hadithList.onItemClick = function(l, v, p, i) showHadithPlayer(i + 1) end
end

-- HADITH - player
function showHadithPlayer(bookIdx)
  screen = "hadithplayer"
  -- FIX: Next/Prev Book screen ko naye sirey se render to kar rahe thay,
  -- lekin purani Book ki audio (duaMp) aur uska updateTask kabhi properly
  -- band nahi hota tha - is liye naye screen ke buttons purani audio ko
  -- control kar rahe thay, jo "kaam nahi kar raha" jaisa lagta tha.
  stopPlayer()
  local b = hadithBooks[bookIdx]
  local localPath = getHadithLocal(b)
  local playUrl = File(localPath).exists() and localPath or buildHadithUrl(b)
  local isDownloaded = File(localPath).exists()
  local bgColor, textColor = getThemeColors()

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
    -- FIX (v2.1): ab bilkul Quran Majeed Surah Player jaisa hi row hai -
    -- Prev Book / Rewind / Play-Pause / Forward / Next Book
    {LinearLayout, orientation=0, gravity="center", layout_width=-1,
      {Button, id="hdPrevBtn", text="⏮", textSize="14sp", layout_weight=1, layout_margin="2dp"},
      {Button, id="hdRwdBtn", text="⏪ "..seekSeconds.."s", textSize="16sp", layout_weight=1, layout_margin="2dp"},
      {Button, id="hdPlayPause", text="▶ " .. tr("Play"), textSize="16sp", typeface=Typeface.DEFAULT_BOLD, layout_weight=1.5, layout_margin="2dp"},
      {Button, id="hdFwdBtn", text=seekSeconds.."s ⏩", textSize="16sp", layout_weight=1, layout_margin="2dp"},
      {Button, id="hdNextBtn", text="⏭", textSize="14sp", layout_weight=1, layout_margin="2dp"}
    },
    {Button, id="hdDownload", text=isDownloaded and "🗑 Delete Offline" or "⬇️ Download", textSize="14sp", layout_width=-1, layout_marginTop="20dp", backgroundColor=isDownloaded and "#C62828" or "#1976D2", textColor=-1},
    {LinearLayout, orientation=0, gravity="center", layout_marginTop="30dp", layout_width=-1,
      {Button, text="Book List", layout_weight=1, layout_marginRight="10dp", onClick=function() showHadithScreen() end},
      {Button, text="Exit App", layout_weight=1, backgroundColor="#C62828", textColor=-1, onClick=function() activity.finish() end}
    }
  })
  applyWallpaper(mainLayout, bgColor)

  hdPrevBtn.onClick = function() if bookIdx > 1 then showHadithPlayer(bookIdx - 1) end end
  hdNextBtn.onClick = function() if bookIdx < #hadithBooks then showHadithPlayer(bookIdx + 1) end end

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
      playReliable(playUrl, localPath, "Bukhari Book " .. b.n, nil, function()
        pcall(function() hdPlayPause.setText("▶ " .. tr("Play")) end)
        if bookIdx < #hadithBooks then showHadithPlayer(bookIdx + 1) end
      end)
    end
  end

  hdDownload.onClick = function()
    if File(localPath).exists() then
      confirmDelete(localPath, function() showHadithPlayer(bookIdx) end)
    else
      local ok, err = pcall(function()
        local req = DownloadManager.Request(Uri.parse(buildHadithUrl(b)))
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

-- TAFSEER-E-QURAN (Dr. Israr Ahmad, Urdu) - list
function showIsrarTafseerScreen()
  screen = "israrlist"
  stopPlayer()
  local bgColor, textColor = getThemeColors()
  local names = {}
  for _, t in ipairs(israrTafseerFiles) do table.insert(names, t.n == 0 and t.title or ("Surah " .. t.n .. ": " .. t.title)) end

  activity.setContentView(loadlayout{
    LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor,
    {LinearLayout, orientation=0, padding="10dp", backgroundColor="#5D4037", layout_width=-1, gravity="center_vertical",
      {Button, text=tr("Back"), onClick=function() showMore() end},
      {TextView, text="Tafseer-e-Quran (Dr. Israr Ahmad)", textSize="15sp", typeface=Typeface.DEFAULT_BOLD, layout_marginLeft="10dp", textColor=-1}
    },
    {TextView, text="Bayan-ul-Quran - Introduction + 114 Surah, Urdu mein", textSize="12sp", textColor="#777777", padding="8dp"},
    {ListView, id="israrList", layout_width=-1, layout_height=0, layout_weight=1}
  })
  applyWallpaper(mainLayout, bgColor)
  israrList.setAdapter(ArrayAdapter(activity, android.R.layout.simple_list_item_1, names))
  israrList.onItemClick = function(l, v, p, i) showIsrarTafseerPlayer(i + 1) end
end

-- TAFSEER-E-QURAN (Dr. Israr Ahmad) - player (Quran Majeed Surah Player jaisa)
function showIsrarTafseerPlayer(idx)
  screen = "israrplayer"
  stopPlayer()
  local t = israrTafseerFiles[idx]
  local localPath = getIsrarTafseerLocal(t)
  local playUrl = File(localPath).exists() and localPath or buildIsrarTafseerUrl(t)
  local isDownloaded = File(localPath).exists()
  local bgColor, textColor = getThemeColors()

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
      {Button, text="List", layout_weight=1, layout_marginRight="10dp", onClick=function() showIsrarTafseerScreen() end},
      {Button, text="Exit App", layout_weight=1, backgroundColor="#C62828", textColor=-1, onClick=function() activity.finish() end}
    }
  })
  applyWallpaper(mainLayout, bgColor)

  izPrevBtn.onClick = function() if idx > 1 then showIsrarTafseerPlayer(idx - 1) end end
  izNextBtn.onClick = function() if idx < #israrTafseerFiles then showIsrarTafseerPlayer(idx + 1) end end

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
      playReliable(playUrl, localPath, t.title, nil, function()
        pcall(function() izPlayPause.setText("▶ " .. tr("Play")) end)
        if idx < #israrTafseerFiles then showIsrarTafseerPlayer(idx + 1) end
      end)
    end
  end

  izDownload.onClick = function()
    if File(localPath).exists() then
      confirmDelete(localPath, function() showIsrarTafseerPlayer(idx) end)
    else
      local ok, err = pcall(function()
        local req = DownloadManager.Request(Uri.parse(buildIsrarTafseerUrl(t)))
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

function showMore()
  screen = "more"
  local bgColor, textColor = getThemeColors()

  activity.setContentView(loadlayout{
    LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor,
    {ScrollView, layout_width=-1, layout_height=0, layout_weight=1,
    {LinearLayout, orientation=1, padding="20dp", layout_width=-1, layout_height=-2,
      {TextView, text="More", textSize="24sp", typeface=Typeface.DEFAULT_BOLD, layout_marginBottom="20dp", textColor=appColorStr},
      {Button, text="30 Para", textSize="18sp", layout_width=-1, layout_marginBottom="15dp", backgroundColor="#2E7D32", textColor=-1, onClick=function() showPara() end},
      {Button, text="Digital Tasbeeh", textSize="18sp", layout_width=-1, layout_marginBottom="15dp", backgroundColor="#00796B", textColor=-1, onClick=function() showTasbeeh() end},
      {Button, text="Bookmarks", textSize="18sp", layout_width=-1, layout_marginBottom="15dp", backgroundColor="#E91E63", textColor=-1, onClick=function() showBookmarksScreen() end},
      {Button, text="99 Names of Allah", textSize="18sp", layout_width=-1, layout_marginBottom="15dp", backgroundColor="#8E24AA", textColor=-1, onClick=function() showNamesOfAllah() end},
      {Button, text="Blessed Names of Prophet", textSize="18sp", layout_width=-1, layout_marginBottom="15dp", backgroundColor="#00695C", textColor=-1, onClick=function() showAsmaNabi() end},
      {Button, text="Poori Quran (Continuous)", textSize="18sp", layout_width=-1, layout_marginBottom="15dp", backgroundColor="#3E2723", textColor=-1, onClick=function() showFullQuranScreen() end},
      {Button, text="Hadith (Sahih Bukhari)", textSize="18sp", layout_width=-1, layout_marginBottom="15dp", backgroundColor="#4E342E", textColor=-1, onClick=function() showHadithScreen() end},
      {Button, text="Tafseer-e-Quran (Dr. Israr Ahmad)", textSize="18sp", layout_width=-1, layout_marginBottom="15dp", backgroundColor="#5D4037", textColor=-1, onClick=function() showIsrarTafseerScreen() end},
      {Button, text="Menu", textSize="18sp", layout_width=-1, layout_marginBottom="15dp", onClick=function() showSettings() end}
    }},
    moreSubTabs("")
  })
  applyWallpaper(mainLayout, bgColor)
end

-- TASBEEH
function showTasbeeh()
  screen = "tasbeeh"
  local targets = {33, 34, 99, 100, 1000, 5000, 10000, 100000, 9999999}
  local targetLabels = {"Target: 33", "Target: 34", "Target: 99", "Target: 100", "Target: 1,000", "Target: 5,000", "Target: 10,000", "Target: 100,000", "Unlimited (No Limit)"}
  local targetIndex = 0
  for i,v in ipairs(targets) do if v == tasbeehTarget then targetIndex = i - 1 break end end

  local bgColor, textColor = getThemeColors()

  activity.setContentView(loadlayout{
    ScrollView, layout_width=-1, layout_height=-1, fillViewport=true, backgroundColor=bgColor,
    {LinearLayout, id="mainLayout", orientation=1, padding="20dp", layout_width=-1, layout_height=-1, gravity="center_horizontal",

      {LinearLayout, orientation=0, layout_width=-1, gravity="center_vertical", layout_marginBottom="10dp",
        {Button, text=tr("Back"), onClick=function() showMore() end},
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
  applyWallpaper(mainLayout, bgColor)

  chkSound.setOnCheckedChangeListener(CompoundButton.OnCheckedChangeListener{onCheckedChanged=function(b, isChecked) tasbeehBeepEnabled=isChecked saveActiveTasbeehState() end})
  chkVib.setOnCheckedChangeListener(CompoundButton.OnCheckedChangeListener{onCheckedChanged=function(b, isChecked) tasbeehVibrateEnabled=isChecked saveActiveTasbeehState() end})
  chkAwake.setOnCheckedChangeListener(CompoundButton.OnCheckedChangeListener{onCheckedChanged=function(b, isChecked)
    if isChecked then activity.getWindow().addFlags(128) else activity.getWindow().clearFlags(128) end
  end})

  categorySpinner.setAdapter(ArrayAdapter(activity, android.R.layout.simple_spinner_dropdown_item, wazaifCategories))
  wazeefaSpinner.setAdapter(ArrayAdapter(activity, android.R.layout.simple_spinner_dropdown_item, wazaifLabels))
  wazeefaSpinner.setSelection(currentWazeefaIndex)
  wazeefaSpinner.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{onItemSelected=function(p, v, pos, id) currentWazeefaIndex=pos txtWazeefaDisplay.setText(wazaifArabicText[pos+1]) saveActiveTasbeehState() end})

  targetSpinner.setAdapter(ArrayAdapter(activity, android.R.layout.simple_spinner_dropdown_item, targetLabels))
  targetSpinner.setSelection(targetIndex)
  targetSpinner.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{onItemSelected=function(p, v, pos, id) tasbeehTarget=targets[pos+1] tasbeehProgress.setMax(tasbeehTarget) if tasbeehTarget==9999999 then tasbeehProgress.setMax(100) tasbeehProgress.setProgress(100) end saveActiveTasbeehState() end})

  btnTap.onClick = function()
    if tasbeehVibrateEnabled then doVibrate(30) end
    tasbeehCount = tasbeehCount + 1
    lifetimeZikrTotal = lifetimeZikrTotal + 1
    txtCount.setText(tostring(tasbeehCount))
    txtLifetime.setText(tostring(lifetimeZikrTotal))
    prefs.edit().putInt("lifetimeZikrTotal", lifetimeZikrTotal).apply()

    if tasbeehTarget ~= 9999999 then tasbeehProgress.setProgress(tasbeehCount) end
    saveActiveTasbeehState()

    if tasbeehCount == tasbeehTarget and tasbeehTarget ~= 9999999 then
      if tasbeehBeepEnabled then playBeep() end if tasbeehVibrateEnabled then doVibrate(500) end
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
      saveActiveTasbeehState()
    end
  end

  btnClearSaved.onClick = function() prefs.edit().remove("savedCount").remove("savedTarget").remove("savedWazeefa").apply() Toast.makeText(activity, "Saved Data Cleared!", 0).show() end

  btnReset.onClick = function() tasbeehCount=0 txtCount.setText("0") tasbeehProgress.setProgress(0) saveActiveTasbeehState() if tasbeehVibrateEnabled then doVibrate(50) end end
end

-- SURAH LIST
function showSurahList()
  screen = "surahlist"
  local bgColor, textColor = getThemeColors()

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
      {Button, text=tr("Back"), onClick=function() showHome() end},
      {TextView, text="Quran Pak (use the search bar on Home to find a Surah)", textSize="14sp", layout_marginLeft="10dp", textColor=-1}
    },
    {ListView, id="list", layout_width=-1, layout_height=0, layout_weight=1},
    bottomTabs("quran")
  })
  applyWallpaper(mainLayout, bgColor)

  local adapter = ArrayAdapter(activity, android.R.layout.simple_list_item_1, filteredSurahs)
  list.setAdapter(adapter)

  list.onItemClick = function(l, v, p, i) currentIndex = filteredIndices[i + 1] showPlayer(currentIndex) end

  list.onItemLongClick = function(l, v, p, i)
    local sIndex = filteredIndices[i + 1]
    local sName = surahNames[sIndex]

    AlertDialog.Builder(activity).setTitle(sName).setItems({"▶️ Play", "🔖 Bookmark", "📌 Pin", "📋 Copy", "🗑️ Delete", "❌ Cancel"}, {onClick=function(dialog, which)
      if which == 0 then currentIndex = sIndex showPlayer(currentIndex)
      elseif which == 1 then table.insert(bookmarks, sIndex) saveBookmarks() Toast.makeText(activity, "Bookmarked!", 0).show()
      elseif which == 2 then pinned[sIndex] = not pinned[sIndex] savePinned() showSurahList()
      elseif which == 3 then activity.getSystemService(Context.CLIPBOARD_SERVICE).setPrimaryClip(ClipData.newPlainText("Surah", sName)) Toast.makeText(activity, "Copied!", 0).show()
      elseif which == 4 then deletedSurahs[sIndex] = true saveDeleted() showSurahList()
      end
    end}).show()
    return true
  end
end

-- BOOKMARKS
function showBookmarksScreen()
  screen = "bookmarks"
  local bgColor, textColor = getThemeColors()

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
      {Button, text=tr("Back"), onClick=function() showMore() end},
      {EditText, id="etSearchBm", hint="Search Bookmarks...", layout_marginLeft="10dp", layout_weight=1, singleLine=true, textColor=-1, hintTextColor="#DDDDDD"},
      {Button, text="🗑️ Clear", layout_marginLeft="5dp", onClick=function() bookmarks = {} saveBookmarks() showBookmarksScreen() end}
    },
    {ListView, id="bmList", layout_width=-1, layout_height=-1}
  })
  applyWallpaper(mainLayout, bgColor)

  local adapter = ArrayAdapter(activity, android.R.layout.simple_list_item_1, filteredBms)
  bmList.setAdapter(adapter)

  etSearchBm.addTextChangedListener(TextWatcher{onTextChanged=function(c) loadBm(tostring(c):lower()) adapter = ArrayAdapter(activity, android.R.layout.simple_list_item_1, filteredBms) bmList.setAdapter(adapter) end})
  bmList.onItemClick = function(l, v, p, i) hideKeyboard(etSearchBm) if #bookmarks > 0 then currentIndex = filteredIndices[i + 1] showPlayer(currentIndex) end end
  bmList.onItemLongClick = function(l, v, p, i)
    hideKeyboard(etSearchBm)
    if #bookmarks > 0 then
      local realIndex = filteredIndices[i+1]
      AlertDialog.Builder(activity).setTitle("Options").setItems({"▶️ Play", "🔖 Remove", "❌ Cancel"}, {onClick=function(d, w)
        if w == 0 then currentIndex = realIndex showPlayer(currentIndex)
        elseif w == 1 then for idx, val in ipairs(bookmarks) do if val == realIndex then table.remove(bookmarks, idx) break end end saveBookmarks() showBookmarksScreen() end
      end}).show()
    end return true
  end
end

-- SETTINGS
function showSettings()
  screen = "settings"
  local bgColor, textColor = getThemeColors()

  local reciterNames = {} for i, v in ipairs(reciters) do table.insert(reciterNames, v.name) end
  local speedLabels = {"0.75x", "1.0x (Normal)", "1.25x", "1.5x", "2.0x"} local speedValues = {0.75, 1.0, 1.25, 1.5, 2.0}
  local speedIndex = 1 for i,v in ipairs(speedValues) do if v == playbackSpeed then speedIndex = i - 1 break end end
  local sleepLabels = {"Off", "15 Minutes", "30 Minutes", "45 Minutes", "60 Minutes"} local sleepValues = {0, 15, 30, 45, 60}
  local sleepIndex = 0 for i,v in ipairs(sleepValues) do if v == sleepTimerMinutes then sleepIndex = i - 1 break end end
  local seekLabels = {"5 Seconds", "10 Seconds", "15 Seconds", "20 Seconds", "25 Seconds", "30 Seconds", "1 Minute"} local seekValues = {5, 10, 15, 20, 25, 30, 60}
  local seekIndex = 1 for i,v in ipairs(seekValues) do if v == seekSeconds then seekIndex = i - 1 break end end
  -- NAYA (v2.1): Tarjuma (Translation) Off/Urdu spinner
  local tarjumaLabels = {"Off", "Urdu", "Hindi", "Punjabi", "English"}
  local tarjumaIndex = 0 for i,v in ipairs(tarjumaLabels) do if v == translationMode then tarjumaIndex = i - 1 break end end
  local urduVoiceLabels = {"Shamshad Ali Khan", "Farhat Hashmi"}
  local urduVoiceValues = {"Shamshad", "Farhat"}
  local urduVoiceIndex = 0 for i,v in ipairs(urduVoiceValues) do if v == urduVoice then urduVoiceIndex = i - 1 break end end

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
      {TextView, text="App Preferences:", textSize="16sp", textColor=appColorStr, typeface=Typeface.DEFAULT_BOLD},
      {CheckBox, id="chkAutoNext", text="Auto Next Surah Mode", textSize="16sp", layout_marginTop="10dp", checked=autoNextMode, textColor=textColor},

      {Button, text="💬 " .. tr("Feedback & Support"), textSize="16sp", layout_width=-1, layout_marginTop="30dp", backgroundColor="#607D8B", textColor=-1, onClick=function() showFeedback() end},
      {Button, text="Social Media Support", textSize="16sp", layout_width=-1, layout_marginTop="10dp", backgroundColor="#00695C", textColor=-1, onClick=function() showSocialMedia() end},
      {Button, text="ℹ️ " .. tr("About App"), textSize="16sp", layout_width=-1, layout_marginTop="10dp", backgroundColor=appColorStr, textColor=-1, onClick=function() showAbout() end},

      {LinearLayout, orientation=0, gravity="center", layout_marginTop="20dp", layout_width=-1,
        {Button, text=tr("Back"), layout_weight=1, layout_marginRight="10dp", onClick=function() showMore() end},
        {Button, text="Exit App", layout_weight=1, backgroundColor="#C62828", textColor=-1, onClick=function() activity.finish() end}
      }
    }
  })
  applyWallpaper(mainLayout, bgColor)

  reciterSpinner.setAdapter(ArrayAdapter(activity, android.R.layout.simple_spinner_dropdown_item, reciterNames))
  reciterSpinner.setSelection(math.min(currentReciter, #reciters) - 1)
  reciterSpinner.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{onItemSelected=function(p,v,pos,id) currentReciter=pos+1 end})
  seekSpinner.setAdapter(ArrayAdapter(activity, android.R.layout.simple_spinner_dropdown_item, seekLabels)) seekSpinner.setSelection(seekIndex) seekSpinner.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{onItemSelected=function(p,v,pos,id) seekSeconds=seekValues[pos+1] end})
  speedSpinner.setAdapter(ArrayAdapter(activity, android.R.layout.simple_spinner_dropdown_item, speedLabels)) speedSpinner.setSelection(speedIndex) speedSpinner.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{onItemSelected=function(p,v,pos,id) playbackSpeed=speedValues[pos+1] end})
  sleepSpinner.setAdapter(ArrayAdapter(activity, android.R.layout.simple_spinner_dropdown_item, sleepLabels)) sleepSpinner.setSelection(sleepIndex) sleepSpinner.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{onItemSelected=function(p,v,pos,id) sleepTimerMinutes=sleepValues[pos+1] end})
  tarjumaSpinner.setAdapter(ArrayAdapter(activity, android.R.layout.simple_spinner_dropdown_item, tarjumaLabels)) tarjumaSpinner.setSelection(tarjumaIndex) tarjumaSpinner.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{onItemSelected=function(p,v,pos,id) saveTranslationMode(tarjumaLabels[pos+1]) end})
  urduVoiceSpinner.setAdapter(ArrayAdapter(activity, android.R.layout.simple_spinner_dropdown_item, urduVoiceLabels)) urduVoiceSpinner.setSelection(urduVoiceIndex) urduVoiceSpinner.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{onItemSelected=function(p,v,pos,id) saveUrduVoice(urduVoiceValues[pos+1]) end})
  chkAutoNext.setOnCheckedChangeListener(CompoundButton.OnCheckedChangeListener{onCheckedChanged=function(b, isChecked) autoNextMode=isChecked end})
end

-- SOCIAL MEDIA SUPPORT
function showSocialMedia()
  screen = "socialmedia"
  local bgColor, textColor = getThemeColors()

  activity.setContentView(loadlayout{
    ScrollView, layout_width=-1, layout_height=-1, fillViewport=true, backgroundColor=bgColor,
    {LinearLayout, id="mainLayout", orientation=1, padding="20dp", layout_width=-1, layout_height=-1, gravity="center_horizontal",
      {TextView, text="Social Media Support", textSize="24sp", typeface=Typeface.DEFAULT_BOLD, layout_marginBottom="20dp", layout_marginTop="10dp", textColor=appColorStr},
      {TextView, text="Community: WhatsApp Group", textSize="12sp", textColor="#777777", layout_width=-1, layout_marginTop="10dp"},
      {Button, text="Join WhatsApp Community", textSize="14sp", layout_width=-1, layout_marginBottom="10dp", backgroundColor="#25D366", textColor=-1, onClick=function() openLinkAndClose("https://chat.whatsapp.com/ItdQOG8lw5E6DKsxx9iNSd") end},
      {TextView, text="Channel: Bridge Tech Welfare", textSize="12sp", textColor="#777777", layout_width=-1, layout_marginTop="10dp"},
      {Button, text="Follow WhatsApp Channel", textSize="14sp", layout_width=-1, layout_marginBottom="10dp", backgroundColor="#128C7E", textColor=-1, onClick=function() openLinkAndClose("https://whatsapp.com/channel/0029VbCJfWSAojYuaMuB9E1t") end},
      {TextView, text="Channel: Bridge Tech Welfare (Telegram)", textSize="12sp", textColor="#777777", layout_width=-1, layout_marginTop="10dp"},
      {Button, text="Join Telegram Channel", textSize="14sp", layout_width=-1, layout_marginBottom="10dp", backgroundColor="#0088CC", textColor=-1, onClick=function() openLinkAndClose("https://t.me/+NF0bOu66afYxYWM0") end},
      {TextView, text="YouTube Channel: Instructor of BTW", textSize="12sp", textColor="#777777", layout_width=-1, layout_marginTop="10dp"},
      {Button, text="Subscribe YouTube Channel", textSize="14sp", layout_width=-1, layout_marginBottom="10dp", backgroundColor="#FF0000", textColor=-1, onClick=function() openLinkAndClose("https://youtube.com/@instructor-of-btw?si=nXc_isZVvMV8OQoc") end},
      {TextView, text="YouTube Channel: Technology Information", textSize="12sp", textColor="#777777", layout_width=-1, layout_marginTop="10dp"},
      {Button, text="Subscribe YouTube Channel", textSize="14sp", layout_width=-1, layout_marginBottom="30dp", backgroundColor="#FF0000", textColor=-1, onClick=function() openLinkAndClose("https://www.youtube.com/@Technologyinformation-y4g") end},
      {Button, text=tr("Back"), layout_width=-1, backgroundColor=appColorStr, textColor=-1, onClick=function() showSettings() end}
    }
  })
  applyWallpaper(mainLayout, bgColor)
end

-- FEEDBACK AND SUPPORT
function showFeedback()
  screen = "feedback"
  local bgColor, textColor = getThemeColors()

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
      {Button, text="📱 " .. tr("Direct WhatsApp Feedback"), textSize="14sp", layout_width=-1, layout_marginBottom="20dp", backgroundColor="#25D366", textColor=-1, onClick=function() openLinkAndClose(waNumberUrl) end},
      {Button, text="💬 Join WhatsApp Group 1", textSize="14sp", layout_width=-1, layout_marginBottom="10dp", backgroundColor="#075E54", textColor=-1, onClick=function() openLinkAndClose("https://chat.whatsapp.com/DJY36CzqJdO7uYMsUi1fXp") end},
      {Button, text="💬 Join WhatsApp Group 2", textSize="14sp", layout_width=-1, layout_marginBottom="10dp", backgroundColor="#075E54", textColor=-1, onClick=function() openLinkAndClose("https://chat.whatsapp.com/KzqqC44433PF2iwsXNd93p") end},
      {Button, text="💬 Join WhatsApp Group 3", textSize="14sp", layout_width=-1, layout_marginBottom="10dp", backgroundColor="#075E54", textColor=-1, onClick=function() openLinkAndClose("https://chat.whatsapp.com/FsiATGe2BAb2rfNWolL3k4") end},
      {Button, text="📢 Follow WhatsApp Channel", textSize="14sp", layout_width=-1, layout_marginBottom="10dp", backgroundColor="#128C7E", textColor=-1, onClick=function() openLinkAndClose("https://whatsapp.com/channel/0029Vb7I39ILikgHRF0PBV3k") end},
      {Button, text="📺 Subscribe YouTube Channel", textSize="14sp", layout_width=-1, layout_marginBottom="30dp", backgroundColor="#FF0000", textColor=-1, onClick=function() openLinkAndClose("https://youtube.com/@friendtagresourcesteam?si=mT_M3jqVLcpwlRjN") end},
      {Button, text=tr("Back"), layout_width=-1, backgroundColor=appColorStr, textColor=-1, onClick=function() showSettings() end}
    }
  })
  applyWallpaper(mainLayout, bgColor)
end

-- ABOUT
function showAbout()
  screen = "about"
  local bgColor, textColor = getThemeColors()

  local infoText = [[
Assalam-o-Alaikum!
Version: 2.1

--- WHAT'S NEW IN V2.1 ---

Added (New Features):
- Word-by-Word (Hifz) mode: reads a Surah's Ayat one Arabic word at a
  time (Alafasy audio), for memorization - open from any Surah's "..."
  menu, pick a starting Ayat, tap each word to hear it, or turn Auto ON
  to play through automatically
- Tarjuma (Translation): Off/Urdu/Hindi/Punjabi/English - pick from
  Settings. Urdu and English also play automatically after each Ayat in
  Ayat-ba-Ayat and Ruku mode, and download together with the Ayat audio
  for offline use. Two Urdu voices available (Shamshad Ali Khan / Farhat
  Hashmi) and two Punjabi/Hindi/English voices researched and verified
- Poori Quran (Continuous): two full-Quran single recordings (with Urdu
  translation mixed in) - Al-Minshawi and Al-Hosary - with Play/Pause,
  Rewind/Forward, scrub, and offline download
- Hadith (Sahih Bukhari, English): all 97 Kitab (Books), each with a
  full Surah-Player-style player (Prev/Rewind/Play/Forward/Next Book,
  offline download)
- Tafseer-e-Quran (Bayan-ul-Quran) by Dr. Israr Ahmad, Urdu: Introduction
  + all 114 Surahs, same full player style, offline download
- 40 new "Rabbana" Quranic duas added to Daily Masnoon Duas
- Advanced Home search: search and jump straight into a specific Ayat
  (e.g. type "Baqarah 255"), search and play any of the 30 Para directly,
  search/select Tarjuma language, and tapping a Surah now offers a
  Play/Ayat-ba-Ayat/Ruku/Word-by-Word choice
- Aaj ki Gregorian date, Islamic (Hijri) date, and battery % now shown
  on Home
- Copyable/shareable error dialogs (Copy + Share buttons) wherever a
  download can fail, so problems are easy to report

Fixed (Bugs):
- Surah download crash: "Invalid value for visibility" (Android security
  restriction on public-folder downloads) - affected Surah, Dua, and
  background-download-fallback downloads
- Storage permission was never requested, so Storage Manager always
  showed 0 MB/0 files
- 99 Names "Play" never turned into a real Pause button (always
  restarted) - now a proper toggle, plus offline download added
- Prayer times on Home were fetched once and cached forever, never
  changing day to day - now auto-refresh once per day; API switched to
  HTTPS for reliability
- Word-by-Word: several rounds of audio/timing fixes (seek-before-ready
  race condition, missing audio stream type, approximate-timing fallback
  when exact per-word data isn't available for an Ayat)
- Hadith player Next/Previous Book not stopping the previous audio

Removed:
- Storage Manager and Progress Tracker (not needed)

More section: every screen (Para, Tasbeeh, Bookmarks, Names, Blessed
Names, Full Quran, Hadith, Tafseer, Menu) is now reachable both as a big
button on the More screen AND as a quick-switch tab on every sub-screen.

--- CREDITS ---
Lead Developer: Numan Khan.
May Allah accept our continuous efforts!
]]

  activity.setContentView(loadlayout{
    ScrollView, id="mainLayout", layout_width=-1, layout_height=-1, fillViewport=true, backgroundColor=bgColor,
    {LinearLayout, orientation=1, padding="20dp", layout_width=-1, layout_height=-1, gravity="center_horizontal",
      {TextView, text=tr("About App"), textSize="24sp", typeface=Typeface.DEFAULT_BOLD, layout_marginBottom="20dp", layout_marginTop="10dp", textColor=appColorStr},
      {TextView, text=infoText, textSize="14sp", gravity="left", layout_marginBottom="40dp", textColor=textColor},
      {Button, text=tr("Back"), layout_width=-1, backgroundColor=appColorStr, textColor=-1, onClick=function() showSettings() end}
    }
  })
  applyWallpaper(mainLayout, bgColor)
end

-- PLAYER LOGIC HELPERS
function playNextSurah() if currentIndex < #surahNames then currentIndex = currentIndex + 1 showPlayer(currentIndex) end end
function playPrevSurah() if currentIndex > 1 then currentIndex = currentIndex - 1 showPlayer(currentIndex) end end
-- FIX: Toast messages 2 second mein khud ghayab ho jate hain, is liye error
-- ka poora text kabhi nazar/copy nahi hota tha. Ye chhota helper ek Dialog
-- box dikhata hai jo khud band NAHI hota (jab tak user khud OK/Copy na
-- dabaye) - "Copy" button se error seedha clipboard mein copy ho jata hai.
function showErrorDialog(title, errText)
  pcall(function()
    AlertDialog.Builder(activity)
      .setTitle(title or "Error")
      .setMessage(tostring(errText))
      .setPositiveButton("Copy", {onClick=function()
        pcall(function()
          activity.getSystemService(Context.CLIPBOARD_SERVICE).setPrimaryClip(ClipData.newPlainText("Error", tostring(errText)))
          Toast.makeText(activity, "Copy ho gaya!", 0).show()
        end)
      end})
      .setNeutralButton("Share", {onClick=function()
        pcall(function()
          local shareIntent = Intent(Intent.ACTION_SEND)
          shareIntent.setType("text/plain")
          shareIntent.putExtra(Intent.EXTRA_TEXT, tostring(errText))
          activity.startActivity(Intent.createChooser(shareIntent, "Share Error"))
        end)
      end})
      .setNegativeButton("OK", nil)
      .show()
  end)
end

function downloadSurah(url, fileName, title)
  -- FIX: is function mein pehle koi error-handling nahi thi - agar
  -- DownloadManager.enqueue() kisi bhi wajah se (storage permission,
  -- device masla, wagera) fail hota, to sirf ek generic/khamosh error
  -- aata tha, asal wajah kabhi pata nahi chalti thi. Ab pcall se wrap
  -- kar ke asal error message dikhaya jata hai.
  local ok, err = pcall(function()
    local req = DownloadManager.Request(Uri.parse(url))
    req.setTitle(title)
    req.setDescription("Downloading...")
    -- FIX (asal wajah, ab error se confirm ho gayi): Android public
    -- Downloads folder mein save hone wali file ke liye "HIDDEN"
    -- notification allow nahi karta - SecurityException "Invalid value
    -- for visibility: 2" deta hai. VISIBLE_NOTIFY_COMPLETED istemal karte
    -- hain (ek chhota system notification dikhega jab tak download chale,
    -- phir mukammal hone par - koi crash nahi hoga).
    req.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
    -- FIX: pehle setDestinationUri(Uri.fromFile(...)) se raw file path di
    -- ja rahi thi - naye Android (10+) ki "Scoped Storage" restriction ki
    -- wajah se yeh tareeqa kabhi kabhi beech mein hi fail/interrupt ho
    -- jata hai. setDestinationInExternalPublicDir(...) DownloadManager ka
    -- officially-supported, hamesha kaam karne wala tareeqa hai (isay
    -- storage-permission ki bhi zaroorat nahi hoti, DownloadManager khud
    -- is ke liye exempt hota hai) - end result wahi jagah hai
    -- (Downloads/Quran_Files/), sirf tareeqa zyada reliable hai.
    req.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, "Quran_Files/" .. fileName)
    activity.getSystemService(Context.DOWNLOAD_SERVICE).enqueue(req)
  end)
  if ok then
    Toast.makeText(activity, "Download shuru ho gaya... khatam hote hi is Surah screen par wapis aakar offline play karein.", 1).show()
  else
    -- FIX: pehle sirf 2-second wala Toast tha, error text kabhi copy nahi
    -- ho pata tha - ab persistent Dialog + Copy button hai
    showErrorDialog("Download Error", err)
  end
end
function confirmDelete(filePath, onSuccess) AlertDialog.Builder(activity).setTitle("Delete Confirmation").setMessage("Delete this offline file?").setPositiveButton("Yes", {onClick=function() local f=File(filePath) if f.exists() then f.delete() end Toast.makeText(activity,"Deleted",0).show() if onSuccess then onSuccess() end end}).setNegativeButton("No", nil).show() end

-- Surah metadata (Ruku boundaries + Arabic ayah text) - api.alquran.cloud se
-- live fetch hoti hai (guess/hardcode nahi ki, taake ghalat na ho), disk par
-- cache hoti hai taake offline bhi kaam kare. Ayat-ba-Ayat aur Ruku Mode dono
-- isay share karte hain.
local rukuCache = {}
local ayahTextCache = {}

local function getSurahMetaCachePath(surahIdx) return ayahAudioDir .. "meta_surah" .. surahIdx .. ".txt" end

local function saveSurahMetaToDisk(surahIdx, list, texts)
  pcall(function()
    local f = io.open(getSurahMetaCachePath(surahIdx), "w")
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

local function loadSurahMetaFromDisk(surahIdx)
  local path = getSurahMetaCachePath(surahIdx)
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

local function fetchSurahMeta(surahIdx, callback)
  if rukuCache[surahIdx] and ayahTextCache[surahIdx] then callback(rukuCache[surahIdx], ayahTextCache[surahIdx]) return end
  local diskList, diskTexts = loadSurahMetaFromDisk(surahIdx)
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
        saveSurahMetaToDisk(surahIdx, result, texts or {})
        callback(result, ayahTextCache[surahIdx])
      else
        callback(nil, nil)
      end
    end})
  end}).start()
end

--------------------------------------------------
-- WORD-BY-WORD (HIFZ) MODE - v2.1
-- Sirf ek naya, alag-thalag mode hai - koi bhi existing function
-- (playReliable/stopPlayer/mp/duaMp/Ayat-ba-Ayat/Ruku wagera) mein koi
-- tabdeeli nahi ki gayi. Ye mode wahi cheezein reuse karta hai jo v2.0
-- mein pehle se ban chuki hain:
--   - Audio: buildAyahUrl()/getAyahAudioLocal() (Alafasy, everyayah.com) -
--     bilkul wahi jo Ayat-ba-Ayat mode use karta hai
--   - Text: fetchSurahMeta() (api.alquran.cloud, disk-cached) - bilkul
--     wahi jo Ayat-ba-Ayat/Ruku mode use karte hain
-- Sirf NAYI cheez: lafz (word) ki exact timing (kaunsa lafz audio ke
-- kis second par shuru/khatam hota hai) - iske liye ek free, open-source
-- data ("quran-align" project, GitHub) use hota hai jo Alafasy reciter
-- ke liye hi bana hai - is liye yeh bilkul sahi audio ke saath sync hoga.
-- Apna ALAG MediaPlayer (wbwPlayer) hai - mp/duaMp ko bilkul touch nahi
-- karta, is liye kisi bhi purani screen ki playback logic par asar nahi.
--------------------------------------------------
local wbwPlayer = nil
local wbwTimingIndex = nil   -- app session mein ek dafa banta hai: "surah_ayah" -> segments
local wbwWords = nil
local wbwTimings = nil
local wbwWordIdx = 1
local wbwSurahIdx = 1
local wbwAyahNum = 1
local wbwAutoAdv = false
local wbwStopHandle = nil
local wbwPendingWordDuration = 200  -- kitni der (ms) chalna hai, seek complete hone ke baad set hota hai
local wbwOnWordPlaybackDone = nil   -- current WBW screen apna callback yahan set karta hai (auto-advance ke liye)

local wbwTimingUrl = "https://github.com/cpfair/quran-align/releases/download/release-2016-11-24/Alafasy_128kbps.json"
local wbwTimingCachePath = ayahAudioDir .. "wbw_timing_alafasy.json"

local function wbwStopAudio()
  wbwOnWordPlaybackDone = nil
  if wbwStopHandle then pcall(function() handler.removeCallbacks(wbwStopHandle) end) wbwStopHandle = nil end
  if wbwPlayer then
    local oldP = wbwPlayer
    wbwPlayer = nil
    Thread(Runnable{run=function()
      pcall(function() if oldP.isPlaying() then oldP.stop() end end)
      pcall(function() oldP.release() end)
    end}).start()
  end
end

-- GitHub release downloads kabhi kabhi ek "redirect" (302) se guzarte hain
-- (github.com -> objects.githubusercontent.com) - kuch Android versions par
-- HttpURLConnection ise khud follow nahi karta, is liye manually follow
-- karte hain (max 5 hops) taake download reliably chale.
local function httpGetFollowRedirects(urlStr, maxRedirects)
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

-- Alafasy ki poori word-timing JSON (ek hi baar) local cache se, ya download
-- karke, load karta hai aur parse karke wbwTimingIndex banata hai. Sirf app
-- session mein ek dafa hota hai - baad ki har ayat isi table se milti hai.
-- NOTE: agar yeh kisi bhi wajah se fail ho (network, parse), wbwLoadAyah
-- neeche khud-kaar "approximate" per-lafz timing bana leta hai, is liye
-- Word-by-Word feature is failure ki soorat mein bhi dead-end nahi hoti.
local wbwTimingLoadError = nil
local function wbwLoadTimingIndex(onDone)
  if wbwTimingIndex then onDone(true) return end
  Thread(Runnable{run=function()
    local ok, raw = pcall(function()
      if File(wbwTimingCachePath).exists() and File(wbwTimingCachePath).length() > 1000 then
        local f = io.open(wbwTimingCachePath, "r")
        local c = f:read("*a")
        f:close()
        return c
      end
      local res = httpGetFollowRedirects(wbwTimingUrl, 5)
      pcall(function()
        local fo = io.open(wbwTimingCachePath, "w")
        fo:write(res)
        fo:close()
      end)
      return res
    end)
    if not ok or not raw then
      wbwTimingLoadError = "Timing file download nahi hui: " .. tostring(raw)
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
        -- string.format("%d_%d", ...) taake number-to-string conversion
        -- hamesha "2_255" ho, kabhi "2.0_255.0" na ban jaye (jis se lookup
        -- fail ho jata tha aur har lafz "not available" dikhata tha)
        idx[string.format("%d_%d", s, a)] = segs
      end
    end)
    if not pok then wbwTimingLoadError = "Timing file parse nahi hui: " .. tostring(perr) end
    handler.post(Runnable{run=function()
      if pok then wbwTimingIndex = idx end
      onDone(pok)
    end})
  end}).start()
end

-- Ek ayat ke liye: text (fetchSurahMeta se), timing (wbwTimingIndex se),
-- aur audio (buildAyahUrl/getAyahAudioLocal se, already-downloaded ho to
-- wahi use hoti hai) - teeno load karke onReady(true) ya onReady(false, err)
local function wbwLoadAyah(surahIdx, ayahNum, onReady)
  wbwLoadTimingIndex(function(timingOk)
    fetchSurahMeta(surahIdx, function(list, texts)
      if not texts or not texts[ayahNum] then
        onReady(false, "Ayat ka text load nahi hua. Internet check karein.")
        return
      end
      local words = {}
      for w in tostring(texts[ayahNum]):gmatch("%S+") do words[#words+1] = w end
      wbwWords = words

      local segs = (wbwTimingIndex and wbwTimingIndex[string.format("%d_%d", surahIdx, ayahNum)]) or {}
      local tim = {}
      for _, seg in ipairs(segs) do
        local ws, we, st, en = seg[1], seg[2], seg[3], seg[4]
        for i = ws, we - 1 do tim[i+1] = {st, en} end
      end
      local hasExactTiming = next(tim) ~= nil
      wbwTimings = tim
      wbwWordIdx = 1

      local localPath = getAyahAudioLocal(surahIdx, ayahNum)
      local playUrl = File(localPath).exists() and localPath or buildAyahUrl(surahIdx, ayahNum)

      wbwStopAudio()
      local ok = pcall(function()
        wbwPlayer = MediaPlayer()
        -- FIX: pehle yahan setAudioStreamType nahi tha, jo purane Android
        -- (jaise S7) par MediaPlayer ko prepare/play hi nahi hone deta -
        -- yehi wajah thi "koi awaz nahi aati" ki. Ayat-ba-Ayat/Duas mode
        -- (playReliable) mein yeh hamesha set hota hai, ab yahan bhi karte hain.
        pcall(function() wbwPlayer.setAudioStreamType(AudioManager.STREAM_MUSIC) end)
        wbwPlayer.setDataSource(playUrl)
        wbwPlayer.setOnPreparedListener(MediaPlayer.OnPreparedListener{onPrepared=function(p)
          -- SAFETY FALLBACK: agar is ayat ke liye exact per-lafz timing
          -- nahi mili (timing file download/parse fail hui, ya is khaas
          -- ayat ka data quran-align mein maujood nahi), to "not available"
          -- dikhane ki bajaye ayat ki poori audio duration ko lafzon ki
          -- tadaad mein barabar taqseem kar ke ek andazan (approximate)
          -- timing khud bana lete hain - taake Sunein button HAMESHA kaam
          -- kare
          if not hasExactTiming then
            local dur = 0
            pcall(function() dur = p.getDuration() end)
            if dur and dur > 0 and #words > 0 then
              local est = {}
              for i = 1, #words do
                est[i] = {math.floor((i-1) * dur / #words), math.floor(i * dur / #words)}
              end
              wbwTimings = est
            end
          end
          onReady(true, nil, hasExactTiming)
        end})
        -- FIX: seekTo() asynchronous hai - is se pehle start() foran bula
        -- lena (seek poori hone se pehle hi) kabhi kabhi bilkul khamosh
        -- reh jata tha (khaas kar pehli/"cold" seek par). Ab play/pause
        -- dono OnSeekCompleteListener ke andar, seek MUKAMMAL hone ke
        -- BAAD hote hain - is se har lafz reliably bajta hai.
        wbwPlayer.setOnSeekCompleteListener(MediaPlayer.OnSeekCompleteListener{onSeekComplete=function(p)
          pcall(function() p.start() end)
          wbwStopHandle = Runnable{run=function()
            pcall(function() if wbwPlayer and wbwPlayer.isPlaying() then wbwPlayer.pause() end end)
            wbwStopHandle = nil
            if screen == "wbwmode" and wbwOnWordPlaybackDone then wbwOnWordPlaybackDone() end
          end}
          handler.postDelayed(wbwStopHandle, wbwPendingWordDuration)
        end})
        wbwPlayer.setOnErrorListener(MediaPlayer.OnErrorListener{onError=function(p,w,e)
          -- FIX: kuch hosts (yahi everyayah.com bhi) is device/Android
          -- version par seedhe streaming se theek se play nahi hote -
          -- Ayat-ba-Ayat/Duas mode (playReliable) mein isi wajah se
          -- background-download-fallback banaya gaya tha - Word-by-Word
          -- mein bhi ab wahi established tareeqa reuse ho raha hai:
          -- background download, phir local file se retry.
          if playUrl ~= localPath then
            Toast.makeText(activity, "Online stream nahi hui, ab background mein download kar rahe hain...", 1).show()
            Thread(Runnable{run=function()
              local success = directDownload(buildAyahUrl(surahIdx, ayahNum), localPath)
              handler.post(Runnable{run=function()
                if success and screen == "wbwmode" then
                  wbwLoadAyah(surahIdx, ayahNum, onReady)
                else
                  onReady(false, "Ayat ki audio load nahi hui (online aur download dono fail - internet check karein).")
                end
              end})
            end}).start()
          else
            onReady(false, "Ayat ki audio load nahi hui (downloaded file kharab hai).")
          end
          return true
        end})
        wbwPlayer.prepareAsync()
      end)
      if not ok then onReady(false, "Audio player error.") end
    end)
  end)
end

-- Ayat number poochne wala chhota dialog (Update Location wale dialog jaisa) -
-- Surah Player screen ke naye button se khulta hai
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
  wbwSurahIdx = surahIdx
  wbwAyahNum = startAyah or 1
  wbwStopAudio()
  local bgColor, textColor = getThemeColors()

  activity.setContentView(loadlayout{
    LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor,
    {LinearLayout, orientation=0, padding="10dp", backgroundColor="#00695C", layout_width=-1, gravity="center_vertical",
      {Button, text=tr("Back"), contentDescription="Back to Surah player", onClick=function() wbwStopAudio() showPlayer(wbwSurahIdx) end},
      {TextView, id="wbwHeaderTxt", text=surahNames[surahIdx] .. " - Ayat " .. wbwAyahNum .. "/" .. (surahAyahCounts[surahIdx] or "?"), textSize="14sp", typeface=Typeface.DEFAULT_BOLD, layout_marginLeft="10dp", textColor=-1}
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
  applyWallpaper(mainLayout, bgColor)

  local function renderWord()
    if wbwWords and wbwWords[wbwWordIdx] then
      pcall(function()
        wbwWordTxt.setText(wbwWords[wbwWordIdx])
        wbwCountTxt.setText("Lafz " .. wbwWordIdx .. " / " .. #wbwWords)
      end)
    end
  end

  local playCurrentWord
  playCurrentWord = function()
    if wbwStopHandle then pcall(function() handler.removeCallbacks(wbwStopHandle) end) wbwStopHandle = nil end
    if not wbwPlayer then
      Toast.makeText(activity, "Audio abhi taiyar nahi hui, thoda intezar karein.", 0).show()
      return
    end
    local t = wbwTimings and wbwTimings[wbwWordIdx]
    if not t then
      -- FIX: pehle "andazan" (approximate) timing sirf ek dafa, audio
      -- "prepared" hote hi bana li jati thi - us waqt duration kabhi kabhi
      -- 0 milti hai (khaas kar streaming/naye-download-hue files par),
      -- is liye andazan timing khaali reh jati thi aur hamesha "not
      -- available" aata tha. Ab isay YAHIN, Sunein dabane ke waqt banate
      -- hain - is waqt tak duration hamesha reliably mil jati hai.
      local dur = 0
      pcall(function() dur = wbwPlayer.getDuration() end)
      if dur and dur > 0 and wbwWords and #wbwWords > 0 then
        local st = math.floor((wbwWordIdx - 1) * dur / #wbwWords)
        local en = math.floor(wbwWordIdx * dur / #wbwWords)
        t = {st, en}
        wbwTimings = wbwTimings or {}
        wbwTimings[wbwWordIdx] = t
      end
    end
    if not t then
      Toast.makeText(activity, "Is lafz ke liye audio timing nahi mili (audio duration abhi maloom nahi ho saki).", 0).show()
      return
    end
    local st, en = t[1], t[2]
    -- FIX: seekTo() asynchronous hai - foran baad start() bulane se, seek
    -- poori hone se PEHLE hi audio start/pause ho jati thi (khaas kar
    -- pehli/"cold" seek par) - is liye kabhi kabhi bilkul awaz nahi aati
    -- thi (Auto mode mein baad ke lafzon tak seek "warm" ho jati thi, is
    -- liye wahan chalta mehsoos hota tha). Ab start() aur stop-timer dono
    -- OnSeekCompleteListener ke andar, seek MUKAMMAL hone ke BAAD shuru
    -- hote hain.
    wbwPendingWordDuration = math.max(en - st, 200)
    pcall(function() wbwPlayer.seekTo(st) end)
  end

  wbwOnWordPlaybackDone = function()
    if wbwAutoAdv and wbwWords and wbwWordIdx < #wbwWords then
      wbwWordIdx = wbwWordIdx + 1
      renderWord()
      playCurrentWord()
    end
  end

  local function loadAndRender()
    pcall(function()
      wbwStatusTxt.setText("Loading...")
      wbwWordTxt.setText("")
      wbwHeaderTxt.setText(surahNames[wbwSurahIdx] .. " - Ayat " .. wbwAyahNum .. "/" .. (surahAyahCounts[wbwSurahIdx] or "?"))
    end)
    wbwLoadAyah(wbwSurahIdx, wbwAyahNum, function(ok, err, exact)
      if screen ~= "wbwmode" then return end
      if ok then
        pcall(function()
          if exact then
            wbwStatusTxt.setText("Reciter: Mishary Alafasy - lafz par Sunein dabayein")
          else
            wbwStatusTxt.setText("Reciter: Mishary Alafasy - andazan (approximate) taqseem, is ayat ke liye exact lafz-timing maujood nahi")
          end
          saveLastAyahProgress(wbwSurahIdx, wbwAyahNum)
        end)
        renderWord()
      else
        pcall(function() wbwStatusTxt.setText(err or "Load nahi hua.") end)
      end
    end)
  end

  wbwPlayWordBtn.onClick = function() playCurrentWord() end
  wbwPrevWordBtn.onClick = function() if wbwWords and wbwWordIdx > 1 then wbwWordIdx = wbwWordIdx - 1 renderWord() end end
  wbwNextWordBtn.onClick = function() if wbwWords and wbwWordIdx < #wbwWords then wbwWordIdx = wbwWordIdx + 1 renderWord() end end

  wbwAutoBtn.onClick = function()
    wbwAutoAdv = not wbwAutoAdv
    wbwAutoBtn.setText(wbwAutoAdv and "Auto: ON" or "Auto: OFF")
    pcall(function() wbwAutoBtn.setBackgroundColor(Color.parseColor(wbwAutoAdv and "#1565C0" or "#607D8B")) end)
  end

  wbwPrevAyahBtn.onClick = function()
    if wbwAyahNum > 1 then wbwAyahNum = wbwAyahNum - 1
    elseif wbwSurahIdx > 1 then wbwSurahIdx = wbwSurahIdx - 1 wbwAyahNum = surahAyahCounts[wbwSurahIdx] or 1
    else return end
    wbwStopAudio()
    loadAndRender()
  end

  wbwNextAyahBtn.onClick = function()
    local mx = surahAyahCounts[wbwSurahIdx] or 1
    if wbwAyahNum < mx then wbwAyahNum = wbwAyahNum + 1
    elseif wbwSurahIdx < 114 then wbwSurahIdx = wbwSurahIdx + 1 wbwAyahNum = 1
    else return end
    wbwStopAudio()
    loadAndRender()
  end

  loadAndRender()
end

-- AYAT-BA-AYAT MODE (verse by verse - tap an Ayat number to play just that ayah)
function showAyahByAyah(surahIdx, autoPlayAyat)
  screen = "ayahmode"
  local bgColor, textColor = getThemeColors()
  local totalAyahs = surahAyahCounts[surahIdx] or 0
  local alreadyDownloaded = 0
  for a=1, totalAyahs do
    if File(getAyahAudioLocal(surahIdx, a)).exists() then alreadyDownloaded = alreadyDownloaded + 1 end
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
    {TextView, id="txtAyahStatus", text="Reciter: Mishary Alafasy (fixed reciter for this mode). Tap any Ayat below to play it.", textSize="11sp", textColor="#777777", padding="8dp"},
    (lastAyahProgress[surahIdx] and {Button, id="btnResumeAyah", text="Resume from Ayat " .. lastAyahProgress[surahIdx], textSize="13sp", backgroundColor="#FF8F00", textColor=-1, layout_margin="8dp"}) or {LinearLayout, orientation=0, layout_width=-1, layout_height=0},
    {TextView, id="txtDownloadProgress", text="Downloaded for offline: " .. alreadyDownloaded .. " / " .. totalAyahs, textSize="12sp", typeface=Typeface.DEFAULT_BOLD, textColor=appColorStr, padding="8dp"},
    {Button, id="btnDownloadAllAyahs", text="Download All Ayahs for Offline", textSize="13sp", backgroundColor="#1976D2", textColor=-1, layout_margin="8dp"},
    {ListView, id="ayahList", layout_width=-1, layout_height=0, layout_weight=1}
  })
  applyWallpaper(mainLayout, bgColor)

  local function playAyah(n)
    if n < 1 or n > totalAyahs then return end
    pcall(function() txtAyahStatus.setText("Playing Ayat " .. n .. " of " .. totalAyahs) end)
    saveLastAyahProgress(surahIdx, n)
    -- NAYA (v2.1): Tarjuma "Urdu" ON ho to Arabic ke turant baad usi
    -- Ayat ka Urdu tarjuma bhi play hota hai (per-Ayat, everyayah.com)
    playReliable(buildAyahUrl(surahIdx, n), getAyahAudioLocal(surahIdx, n), surahNames[surahIdx] .. " Ayat " .. n, nil, function()
      if translationMode == "Urdu" then
        local uUrl, uPath = currentUrduAyahPair(surahIdx, n)
        playReliable(uUrl, uPath, surahNames[surahIdx] .. " Ayat " .. n .. " (Urdu)", nil, nil)
      elseif translationMode == "English" then
        playReliable(buildEnglishAyahUrl(surahIdx, n), getEnglishAyahAudioLocal(surahIdx, n), surahNames[surahIdx] .. " Ayat " .. n .. " (English)", nil, nil)
      end
    end)
  end

  if lastAyahProgress[surahIdx] and btnResumeAyah then
    btnResumeAyah.onClick = function() playAyah(lastAyahProgress[surahIdx]) end
  end

  ayahList.setAdapter(ArrayAdapter(activity, android.R.layout.simple_list_item_1, buildLabels(nil)))
  ayahList.onItemClick = function(l, v, p, i) playAyah(i + 1) end

  -- NAYA (v2.1): agar search se seedha kisi khaas Ayat par bheja gaya hai
  if autoPlayAyat then playAyah(autoPlayAyat) end

  fetchSurahMeta(surahIdx, function(list, texts)
    if screen == "ayahmode" and texts then
      pcall(function() ayahList.setAdapter(ArrayAdapter(activity, android.R.layout.simple_list_item_1, buildLabels(texts))) end)
    end
  end)

  btnDownloadAllAyahs.onClick = function()
    btnDownloadAllAyahs.setEnabled(false)
    btnDownloadAllAyahs.setText("Downloading...")
    local items = {}
    for a=1, totalAyahs do
      table.insert(items, {url=buildAyahUrl(surahIdx, a), path=getAyahAudioLocal(surahIdx, a)})
    end
    -- NAYA (v2.1): Tarjuma "Urdu"/"English" ON ho to offline ke liye
    -- tarjuma wali Ayat files bhi isi download mein saath shamil ho jati hain
    local totalItems = totalAyahs
    if translationMode == "Urdu" then
      for a=1, totalAyahs do
        local uUrl, uPath = currentUrduAyahPair(surahIdx, a)
        table.insert(items, {url=uUrl, path=uPath})
      end
      totalItems = totalAyahs * 2
    elseif translationMode == "English" then
      for a=1, totalAyahs do
        table.insert(items, {url=buildEnglishAyahUrl(surahIdx, a), path=getEnglishAyahAudioLocal(surahIdx, a)})
      end
      totalItems = totalAyahs * 2
    end
    downloadSequentially(items, 1, 0, function(doneSoFar, idx)
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

-- RUKU MODE - Ruku boundaries (kaunsi ayat se kaunsi ayat tak) api.alquran.cloud
-- se live fetch hoti hain (guess/hardcode nahi ki, taake ghalat na ho), phir
-- Ayat-ba-Ayat wala hi (already offline-proven) audio system reuse hota hai
function showRukuMode(surahIdx)
  screen = "rukumode"
  local bgColor, textColor = getThemeColors()
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
  applyWallpaper(mainLayout, bgColor)

  if lastRukuProgress[surahIdx] and btnResumeRuku then
    btnResumeRuku.onClick = function() showRukuPlayer(surahIdx, lastRukuProgress[surahIdx]) end
  end

  fetchSurahMeta(surahIdx, function(list, texts)
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
  local bgColor, textColor = getThemeColors()
  local list = rukuCache[surahIdx]
  if not list or not list[rukuIdx] then showRukuMode(surahIdx) return end
  local ruku = list[rukuIdx]
  saveLastRukuProgress(surahIdx, rukuIdx)

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
  applyWallpaper(mainLayout, bgColor)

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
    -- NAYA (v2.1): Tarjuma "Urdu" ON ho to har Ayat ke Arabic ke baad
    -- usi Ayat ka Urdu tarjuma bhi bajta hai, phir Ruku aage barhta hai
    playReliable(buildAyahUrl(surahIdx, n), getAyahAudioLocal(surahIdx, n), surahNames[surahIdx] .. " Ayat " .. n, nil, function()
      if translationMode == "Urdu" then
        local uUrl, uPath = currentUrduAyahPair(surahIdx, n)
        playReliable(uUrl, uPath, surahNames[surahIdx] .. " Ayat " .. n .. " (Urdu)", nil, function()
          if screen == "rukuplayer" and isPlayingRuku then playRukuFrom(n + 1) end
        end)
      elseif translationMode == "English" then
        playReliable(buildEnglishAyahUrl(surahIdx, n), getEnglishAyahAudioLocal(surahIdx, n), surahNames[surahIdx] .. " Ayat " .. n .. " (English)", nil, function()
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
      table.insert(items, {url=buildAyahUrl(surahIdx, a), path=getAyahAudioLocal(surahIdx, a)})
    end
    -- NAYA (v2.1): Tarjuma "Urdu"/"English" ON ho to Ruku ke tarjuma
    -- wali Ayat files bhi isi download mein saath shamil ho jati hain
    if translationMode == "Urdu" then
      for a = ruku.startAyah, ruku.endAyah do
        local uUrl, uPath = currentUrduAyahPair(surahIdx, a)
        table.insert(items, {url=uUrl, path=uPath})
      end
      total = total * 2
    elseif translationMode == "English" then
      for a = ruku.startAyah, ruku.endAyah do
        table.insert(items, {url=buildEnglishAyahUrl(surahIdx, a), path=getEnglishAyahAudioLocal(surahIdx, a)})
      end
      total = total * 2
    end
    downloadSequentially(items, 1, 0, function(doneSoFar, idx)
      if screen == "rukuplayer" then pcall(function() txtRukuDlProgress.setText("Downloaded: " .. doneSoFar .. " / " .. total) end) end
    end, function(done)
      if screen == "rukuplayer" then
        pcall(function() btnDownloadRuku.setEnabled(true) btnDownloadRuku.setText("Download This Ruku for Offline") end)
        Toast.makeText(activity, "Ruku download complete: " .. done .. " / " .. total, 1).show()
      end
    end)
  end
end

-- READING MODE
function showReadingMode(index)
  screen = "reading"
  local surahName = surahNames[index]
  local bgColor, textColor = getThemeColors()

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
  applyWallpaper(mainLayout, bgColor)
end

-- PLAYER
function showPlayer(index)
  screen = "player"
  currentIndex = index
  local surahName = surahNames[index]
  saveLastPlayed(currentIndex, currentReciter)

  local sID = string.format("%03d", index)
  local reciterKey = slug(reciters[currentReciter].name)
  local isUrdu = (translationMode == "Urdu")
  local isHindi = (translationMode == "Hindi")
  local isPunjabi = (translationMode == "Punjabi")
  local isEnglish = (translationMode == "English")
  -- NAYA (v2.1): Tarjuma ON ho to combined (Arabic+tarjuma, ek hi file)
  -- audio use hoti hai - isi liye download bhi EK hi hota hai, alag Surah
  -- aur alag tarjuma download nahi karni padti.
  local fileName = isUrdu and ("urdu_surah_"..sID..".mp3") or isHindi and ("hindi_surah_"..sID..".mp3") or isPunjabi and ("punjabi_surah_"..sID..".mp3") or isEnglish and ("english_surah_"..sID..".mp3") or ("reciter_"..reciterKey.."_surah_"..sID..".mp3")
  local localFilePath = downloadDir .. fileName
  local onlineUrl = isUrdu and buildUrduSurahUrl(index) or isHindi and buildHindiSurahUrl(index) or isPunjabi and buildPunjabiSurahUrl(index) or isEnglish and buildEnglishSurahUrl(index) or buildQuranUrl(currentReciter, index)
  local playUrl = File(localFilePath).exists() and localFilePath or onlineUrl
  local isDownloaded = File(localFilePath).exists()

  local bgColor, textColor = getThemeColors()

  activity.setContentView(loadlayout{
    LinearLayout, id="mainLayout", orientation=1, padding="20dp", layout_width=-1, layout_height=-1, gravity="center", backgroundColor=bgColor,
    {TextView, text=isDownloaded and "Offline Mode" or "Online Stream", textSize="14sp", layout_marginBottom="10dp", textColor=appColorStr},
    {TextView, text=surahName, textSize="26sp", typeface=Typeface.DEFAULT_BOLD, layout_marginBottom="10dp", textColor=appColorStr},
    {TextView, text="Reciter: " .. (isUrdu and "Mishary Rashid Alafasy (Urdu Tarjuma ke sath)" or isHindi and "Sheikh Abdur Rehman Al Sudes (Hindi Tarjuma ke sath)" or isPunjabi and "Qari Khushi Muhammad-ul-Azhari (Punjabi Tarjuma ke sath)" or isEnglish and "Ibrahim Walk (English Tarjuma ke sath)" or reciters[currentReciter].name), textSize="14sp", layout_marginBottom="20dp", textColor=textColor},

    {TextView, id="txtSleepTimer", text="", textSize="14sp", textColor="#E91E63", layout_marginBottom="10dp", typeface=Typeface.DEFAULT_BOLD},

    {Button, text="📖 Read Surah Text", textSize="14sp", layout_marginBottom="10dp", backgroundColor="#8E24AA", textColor=-1, onClick=function() showReadingMode(index) end},
    {Button, text="Ayat-ba-Ayat Mode", textSize="14sp", layout_marginBottom="10dp", backgroundColor="#00695C", textColor=-1, onClick=function() showAyahByAyah(index) end},
    {Button, text="Ruku Mode", textSize="14sp", layout_marginBottom="10dp", backgroundColor="#6A1B9A", textColor=-1, onClick=function() showRukuMode(index) end},
    {Button, text="Word-by-Word (Hifz)", textSize="14sp", layout_marginBottom="20dp", backgroundColor="#B71C1C", textColor=-1, contentDescription="Word by word memorization mode", onClick=function() showWbwStartDialog(index) end},

    {SeekBar, id="skBar", layout_width=-1, layout_marginBottom="20dp"},
    {LinearLayout, orientation=0, gravity="center", layout_width=-1,
      {Button, text="⏮", textSize="14sp", layout_weight=1, layout_margin="2dp", onClick=function() playPrevSurah() end},
      {Button, text="⏪ "..seekSeconds.."s", textSize="16sp", layout_weight=1, layout_margin="2dp", onClick=function() seekRewind() end},
      {Button, id="btnPlayPause", text="▶ " .. tr("Play"), textSize="16sp", typeface=Typeface.DEFAULT_BOLD, layout_weight=1.5, layout_margin="2dp", onClick=function() togglePlayPause() end},
      {Button, text=seekSeconds.."s ⏩", textSize="16sp", layout_weight=1, layout_margin="2dp", onClick=function() seekForward() end},
      {Button, text="⏭", textSize="14sp", layout_weight=1, layout_margin="2dp", onClick=function() playNextSurah() end}
    },
    {Button, id="btnDownload", text=isDownloaded and "🗑 Delete Offline" or "⬇️ Download Surah", textSize="14sp", layout_width=-1, layout_marginTop="20dp", backgroundColor=isDownloaded and "#C62828" or "#1976D2", textColor=-1},
    {LinearLayout, orientation=0, gravity="center", layout_marginTop="30dp", layout_width=-1,
      {Button, text="Back to List", layout_weight=1, layout_marginRight="10dp", onClick=function() showSurahList() end},
      {Button, text="Exit App", layout_weight=1, backgroundColor="#C62828", textColor=-1, onClick=function() activity.finish() end}
    }
  })
  applyWallpaper(mainLayout, bgColor)

  btnDownload.onClick = function() if File(localFilePath).exists() then confirmDelete(localFilePath, function() showPlayer(currentIndex) end) else downloadSurah(onlineUrl, fileName, surahName .. (isUrdu and " (Urdu Tarjuma)" or isHindi and " (Hindi Tarjuma)" or isPunjabi and " (Punjabi Tarjuma)" or isEnglish and " (English Tarjuma)" or "")) end end

  stopPlayer(function()
  playerReady = false
  playIntentPending = false
  mp = MediaPlayer() mp.setDataSource(playUrl) mp.prepareAsync()
  mp.setOnErrorListener(MediaPlayer.OnErrorListener{onError=function(p, w, e) Toast.makeText(activity, "Audio error.", 0).show() if btnPlayPause then btnPlayPause.setText("▶ " .. tr("Play")) end return true end})
  mp.setOnPreparedListener(MediaPlayer.OnPreparedListener{onPrepared=function(p)
    if Build.VERSION.SDK_INT >= 23 then p.setPlaybackParams(p.getPlaybackParams().setSpeed(playbackSpeed)) end
    skBar.setMax(p.getDuration())
    playerReady = true
    -- FIX: agar user ne load hone se pehle hi Play dabaya tha, ab turant
    -- start karte hain (aur button ko sahi text dete hain) - warna pehle
    -- ki tarah paused rehta hai jab tak user khud Play na dabaye
    if playIntentPending then
      playIntentPending = false
      pcall(function() p.start() end)
      pcall(function() if btnPlayPause then btnPlayPause.setText("⏸ " .. tr("Pause")) end end)
      startSleepTimer()
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
    saveCompletedSurahs()
    if autoNextMode then playNextSurah() else btnPlayPause.setText("▶ " .. tr("Play")) cancelNotification() end
  end})
  skBar.setOnSeekBarChangeListener(SeekBar.OnSeekBarChangeListener{onProgressChanged=function(s, p, f) if f and mp then mp.seekTo(p) end end})
  end)
end

-- FIX: app close/background hone par audio chalti rehti thi (dusre devices
-- par report hua) - yeh lifecycle hooks framework khud call karta hai (jaise
-- onKeyDown), taake app pause/band hote hi audio bhi ruk jaye
function onPause()
  pcall(function() if mp and mp.isPlaying() then mp.pause() end end)
  pcall(function() if duaMp and duaMp.isPlaying() then duaMp.pause() end end)
  pcall(function() if wbwPlayer and wbwPlayer.isPlaying() then wbwPlayer.pause() end end)
end

function onStop()
  pcall(function() if mp and mp.isPlaying() then mp.pause() end end)
  pcall(function() if duaMp and duaMp.isPlaying() then duaMp.pause() end end)
  pcall(function() if wbwPlayer and wbwPlayer.isPlaying() then wbwPlayer.pause() end end)
end

function onDestroy()
  -- FIX: pehle yahan mp.stop()/mp.release() seedha (turant) call ho rahe the,
  -- jo us safe background-thread mechanism (stopPlayer) ko bypass kar dete
  -- the jo khaas is wajah se banaya gaya tha ke agar player abhi "preparing"
  -- state mein ho to seedha stop/release karna native crash de sakta hai -
  -- yehi exit karte waqt error ki wajah thi. Ab wahi safe tareeqa use hota hai.
  pcall(function() stopPlayer() end)
  pcall(function() cancelNotification() end)
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
    elseif screen == "progresstracker" or screen == "storagemanager" then showMore() return true
    elseif screen == "duaplayer" then showDailyDuas() return true
    elseif screen == "para" then showMore() return true
    elseif screen == "parasurahs" then showPara() return true
    elseif screen == "reading" then showPlayer(currentIndex) return true
    elseif screen == "ayahmode" then showPlayer(currentIndex) return true
    elseif screen == "rukumode" then showPlayer(currentIndex) return true
    elseif screen == "rukuplayer" then showRukuMode(currentIndex) return true
    elseif screen == "wbwmode" then wbwStopAudio() showPlayer(wbwSurahIdx) return true
    elseif screen == "surahlist" then showHome() return true
    elseif screen == "socialmedia" then showSettings() return true
    elseif screen == "fullquranlist" then showMore() return true
    elseif screen == "fullquranplayer" then showFullQuranScreen() return true
    elseif screen == "hadithlist" then showMore() return true
    elseif screen == "hadithplayer" then showHadithScreen() return true
    elseif screen == "israrlist" then showMore() return true
    elseif screen == "israrplayer" then showIsrarTafseerScreen() return true
    elseif screen == "settings" or screen == "tasbeeh" or screen == "bookmarks" then showMore() return true end
  end
  return false
end

--------------------------------------------------
-- NOTIFICATION PLAY/PAUSE (background control, bina app khole)
--------------------------------------------------
-- AndroLua ka apna registerReceiver(filter) + global onReceive(context, intent)
-- convention (onKeyDown jaisa hi) - is se notification ka Play/Pause button
-- app khole bina kaam karta hai
pcall(function() activity.registerReceiver(IntentFilter("quran_majeed_playpause")) end)

function onReceive(context, intent)
  pcall(function()
    local action = intent.getAction()
    if action == "quran_majeed_playpause" then
      if mp then
        if mp.isPlaying() then
          mp.pause()
          pcall(function() if btnPlayPause then btnPlayPause.setText("▶ " .. tr("Play")) end end)
        else
          mp.start()
          pcall(function() if btnPlayPause then btnPlayPause.setText("⏸ " .. tr("Pause")) end end)
        end
        pcall(function() showPlaybackNotification(surahNames[currentIndex] or "Quran Majeed", "Reciter: " .. (reciters[currentReciter] and reciters[currentReciter].name or "")) end)
      elseif duaMp then
        if duaMp.isPlaying() then duaMp.pause() else duaMp.start() end
      end
    end
  end)
end

--------------------------------------------------
-- APP START
--------------------------------------------------
-- FIX (v2.1, retry with safety): Storage permission (Android 6+) kabhi
-- nahi maangi gayi thi - is wajah se listFiles() (Storage Manager) hamesha
-- khaali/0 wapis deta tha. Pehli koshish mein onRequestPermissionsResult
-- handler define nahi kiya gaya tha - jab Android permission dialog band
-- karke wapis app ko batata hai, agar yeh function maujood na ho to yeh
-- poori app crash kar sakta hai. Ab dono cheezein sath hain: request bhi,
-- aur is ka result handler bhi (khali/no-op hi sahi, lekin maujood zaroor).
function onRequestPermissionsResult(requestCode, permissions, grantResults)
  -- Kuch khaas karne ki zaroorat nahi - agar permission mil gayi, agli
  -- baar jab Storage Manager khulega ya download hoga, khud kaam kar
  -- jayega. Sirf is function ka maujood hona hi zaroori hai.
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

showHome()