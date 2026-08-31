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
  {cat="Khaana Peena", title="Khana Khane Ke Baad", ar="الْحَمْدُ لِلَّهِ الَّذِي أَطْعَمَنِي هَٰذَا وَرَزَقَنِيهِ مِنْ غَيْرِ حَوْلٍ مِنِّي وَلَا قُوَّةٍ", ur="تمام تعریفیں اللہ کے لیے جس نے مجھے یہ کھلایا اور رزق دیا", tip="Khana khatam hone ke baad parhein", audio="", src=""},
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
}
local function getDuaAudioLocal(d) return duaAudioDir .. "dua_" .. slug(d.title) .. ".mp3" end

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
      pcall(function()
        local dm = activity.getSystemService(Context.DOWNLOAD_SERVICE)
        local req = DownloadManager.Request(Uri.parse(url))
        req.setTitle(label)
        req.setNotificationVisibility(DownloadManager.Request.VISIBILITY_HIDDEN)
        req.setDestinationUri(Uri.fromFile(File(cachePath)))
        dm.enqueue(req)
      end)
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

local function togglePlayPause()
  if not mp then return end
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
  return {LinearLayout, orientation=0, layout_width=-1, backgroundColor="#1A000000",
    {Button, text="Para", textSize="12sp", layout_weight=1, backgroundColor=tabColor("para"), textColor=tabTextColor("para"), contentDescription="30 Para tab", onClick=function() showPara() end},
    {Button, text="Tasbeeh", textSize="12sp", layout_weight=1, backgroundColor=tabColor("tasbeeh"), textColor=tabTextColor("tasbeeh"), contentDescription="Digital Tasbeeh tab", onClick=function() showTasbeeh() end},
    {Button, text="Bookmarks", textSize="12sp", layout_weight=1, backgroundColor=tabColor("bookmarks"), textColor=tabTextColor("bookmarks"), contentDescription="Bookmarks tab", onClick=function() showBookmarksScreen() end},
    {Button, text="Names", textSize="12sp", layout_weight=1, backgroundColor=tabColor("names"), textColor=tabTextColor("names"), contentDescription="99 Names tab", onClick=function() showNamesOfAllah() end},
    {Button, text="Menu", textSize="12sp", layout_weight=1, backgroundColor=tabColor("menu"), textColor=tabTextColor("menu"), contentDescription="Menu tab", onClick=function() showSettings() end},
    {Button, text="Home", textSize="12sp", layout_weight=1, backgroundColor=tabColor("home"), textColor=tabTextColor("home"), contentDescription="Back to Home tab", onClick=function() showHome() end}
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
    table.insert(idx, {label="Surah: " .. name, action=function() showPlayer(i) end})
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

-- 1. HOME
function showHome()
  screen = "home"
  stopPlayer()
  activity.getWindow().clearFlags(128)
  local bgColor, textColor = getThemeColors()
  local spot = pickSpotlight()
  local searchIndex = nil -- built lazily on first keystroke

  activity.setContentView(loadlayout{
    LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor, focusable=true, focusableInTouchMode=true,
    {TextView, text="Quran Majeed v2.0", textSize="24sp", typeface=Typeface.DEFAULT_BOLD, gravity="center", padding="10dp", textColor=appColorStr, contentDescription="Quran Majeed, version 2 point 0"},
    {LinearLayout, orientation=0, layout_width=-1, padding="10dp", gravity="center_vertical",
      {EditText, id="etHomeSearch", hint="Search Surah, Reciter, or Dua...", layout_weight=1, singleLine=true, textColor=textColor, hintTextColor="#888888"},
      {Button, id="btnHomeSearch", text="Search", textSize="13sp", layout_marginLeft="5dp", backgroundColor=appColorStr, textColor=-1, contentDescription="Search"}
    },
    {TextView, id="txtHomeSearchStatus", text="", textSize="11sp", textColor="#777777", padding="4dp"},
    {ListView, id="homeSearchResults", layout_width=-1, layout_height="260dp"},
    {ScrollView, id="homeScroll", layout_width=-1, layout_height=0, layout_weight=1,
    {LinearLayout, orientation=1, gravity="center_horizontal", padding="20dp", layout_width=-1, layout_height=-2,

      {LinearLayout, orientation=1, layout_width=-1, padding="15dp", layout_marginBottom="15dp", backgroundColor="#1A000000",
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
                Thread(Runnable{
                  run=function()
                    local success, result = pcall(function()
                      local urlStr = "http://api.aladhan.com/v1/timingsByCity?city="..URLEncoder.encode(c).."&country="..URLEncoder.encode(cntry).."&method=1"
                      local conn = URL(urlStr).openConnection()
                      local reader = BufferedReader(InputStreamReader(conn.getInputStream()))
                      local res = "" local line = reader.readLine()
                      while line do res = res..line line = reader.readLine() end
                      reader.close() return res
                    end)
                    activity.runOnUiThread(Runnable{
                      run=function()
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
                            prefs.edit().putString("userCity", c).putString("userCountry", cntry).putString("pFajr", f).putString("pDhuhr", d).putString("pAsr", a).putString("pMaghrib", m).putString("pIsha", i).putString("hijriDate", savedHijriDate).apply()
                            showHome() Toast.makeText(activity, "Updated successfully!", 0).show()
                          else Toast.makeText(activity, "City not found!", 0).show() end
                        else Toast.makeText(activity, "Network error.", 0).show() end
                      end
                    })
                  end
                }).start()
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
      pcall(function()
        local req = DownloadManager.Request(Uri.parse(d.audio)) req.setTitle(d.title) req.setDescription("Downloading dua audio...") req.setNotificationVisibility(DownloadManager.Request.VISIBILITY_HIDDEN) req.setDestinationUri(Uri.fromFile(File(localPath)))
        activity.getSystemService(Context.DOWNLOAD_SERVICE).enqueue(req)
      end)
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
      {Button, text=tr("Back"), contentDescription="Back to Home", onClick=function() showHome() end},
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

  activity.setContentView(loadlayout{
    LinearLayout, id="mainLayout", orientation=1, layout_width=-1, layout_height=-1, backgroundColor=bgColor,
    {LinearLayout, orientation=0, padding="10dp", backgroundColor=appColorStr, layout_width=-1, gravity="center_vertical",
      {Button, text=tr("Back"), onClick=function() showMore() end},
      {TextView, text=tr("99 Names of Allah"), textSize="18sp", typeface=Typeface.DEFAULT_BOLD, layout_marginLeft="10dp", textColor=-1}
    },
    {Button, text="▶️ Play Full Audio (All 99 Names)", textSize="14sp", layout_width=-1, layout_margin="10dp", backgroundColor="#8E24AA", textColor=-1, onClick=function()
      playReliable({
        "https://archive.org/download/99-names-of-allah-asma-ul-husna/99%20names%20of%20Allah%20%20Asma%20Ul%20husna.mp3",
        "https://archive.org/download/AsmaulHusnaMP3/Asmaul%20Husna%20dan%20Artinya%20Asmaul%20Husna%20Mp3%20Asmaul%20Husna%20Beserta%20Artinya%2099%20Asmaul%20Husna%20Asma%20Ul%20Husna%2099%20Nama%20Allah%20TVRI%20Nasional%20Asma%20Ul%20Husna%20TV3%20Dzikir%20Ary%20Ginanjar%20Agustian%20Names%20of%20Allah%20sifat-sifat%20Allah%20pengertian%20asmaul%20husna.mp3",
        "https://archive.org/download/asma-ul-husna-99-names-of-allah/Asma_ul_Husna.mp3"
      }, duaAudioDir .. "asma_ul_husna_full.mp3", "99 Names of Allah - Full Audio", nil, nil)
    end},
    {ScrollView, layout_width=-1, layout_height=-1,
      listLayout
    }
  })
  applyWallpaper(mainLayout, bgColor)
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
      {Button, text="Progress Tracker", textSize="18sp", layout_width=-1, layout_marginBottom="15dp", backgroundColor="#FF8F00", textColor=-1, onClick=function() showProgressTracker() end},
      {Button, text="Storage Manager", textSize="18sp", layout_width=-1, layout_marginBottom="15dp", backgroundColor="#455A64", textColor=-1, onClick=function() showStorageManager() end},
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
Version: 2.0

--- WHAT'S NEW IN V2.0 ---

Removed:
- Resume Last Played button, Downloads Library screen
- Settings' Language/Theme/Color/Wallpaper pickers (fixed, simpler UI now)
- Duplicate Quran/Duas buttons from Home (already covered by tabs)
- Duplicate/redundant duas that existed as both text and audio
- Emoji-heavy decoration on new/updated screens

Fixed:
- Reciter mismatch/wrong-voice bug (now tracked by name, not list position)
- Downloads not showing in the phone's Downloads folder
- Downloads silently opening in YouTube Music instead of the app
- Dua/Ruku/Ayat audio not playing online or offline in several cases
- A crash/freeze (CSR + TalkBack) when downloading many Ayahs at once
- Ruku's Pause button restarting instead of actually pausing
- Search results list not appearing when typing
- Keyboard opening automatically on Home
- Surah and Ayat-ba-Ayat auto-playing instead of waiting for Play

Added:
- 4 bottom tabs: Home, Quran, Duas, More (with its own sub-tabs: Para,
  Tasbeeh, Bookmarks, Names, Menu)
- One rotating "spotlight" on Home (ayah / Allah's name / Prophet's
  blessed name / surah name) that changes every time the app opens
- One universal search bar on Home (Surah, Reciter, or Dua - live-filter
  and an explicit Search button)
- Daily Masnoon Duas split into Audio Duas (own full player, downloadable,
  organized by category) and Text Only Duas
- Blessed Names of Prophet Muhammad screen
- Ayat-ba-Ayat mode for every Surah and inside 30 Para - tap any Ayat to
  play just that one, shows the Ayat's Arabic text, fully downloadable
  and works offline
- Ruku mode for every Surah and inside 30 Para - accurate Ruku boundaries,
  play through a Ruku, downloadable, works offline
- Social Media Support section (WhatsApp community/channel, Telegram,
  YouTube channels)
- TalkBack labels in English throughout

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
function downloadSurah(url, fileName, title)
  local req = DownloadManager.Request(Uri.parse(url)) req.setTitle(title) req.setDescription("Downloading...") req.setNotificationVisibility(DownloadManager.Request.VISIBILITY_HIDDEN) req.setDestinationUri(Uri.fromFile(File(downloadDir .. fileName)))
  activity.getSystemService(Context.DOWNLOAD_SERVICE).enqueue(req) Toast.makeText(activity, "Download shuru ho gaya... khatam hote hi is Surah screen par wapis aakar offline play karein.", 1).show()
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

-- AYAT-BA-AYAT MODE (verse by verse - tap an Ayat number to play just that ayah)
function showAyahByAyah(surahIdx)
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
    playReliable(buildAyahUrl(surahIdx, n), getAyahAudioLocal(surahIdx, n), surahNames[surahIdx] .. " Ayat " .. n, nil, nil)
  end

  if lastAyahProgress[surahIdx] and btnResumeAyah then
    btnResumeAyah.onClick = function() playAyah(lastAyahProgress[surahIdx]) end
  end

  ayahList.setAdapter(ArrayAdapter(activity, android.R.layout.simple_list_item_1, buildLabels(nil)))
  ayahList.onItemClick = function(l, v, p, i) playAyah(i + 1) end

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
    downloadSequentially(items, 1, 0, function(doneSoFar, idx)
      if idx % 3 == 0 or idx == totalAyahs then
        if screen == "ayahmode" then pcall(function() txtDownloadProgress.setText("Downloaded for offline: " .. doneSoFar .. " / " .. totalAyahs) end) end
      end
    end, function(done)
      if screen == "ayahmode" then
        pcall(function()
          btnDownloadAllAyahs.setEnabled(true)
          btnDownloadAllAyahs.setText("Download All Ayahs for Offline")
          if done < totalAyahs then
            Toast.makeText(activity, "Downloaded " .. done .. " / " .. totalAyahs .. ". Kuch fail hui - error: " .. lastDownloadError, 1).show()
          else
            Toast.makeText(activity, "Download complete: " .. done .. " / " .. totalAyahs .. " ayahs saved for offline.", 1).show()
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
    playReliable(buildAyahUrl(surahIdx, n), getAyahAudioLocal(surahIdx, n), surahNames[surahIdx] .. " Ayat " .. n, nil, function()
      if screen == "rukuplayer" and isPlayingRuku then playRukuFrom(n + 1) end
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
  local fileName = "reciter_"..reciterKey.."_surah_"..sID..".mp3"
  local localFilePath = downloadDir .. fileName
  local playUrl = File(localFilePath).exists() and localFilePath or buildQuranUrl(currentReciter, index)
  local isDownloaded = File(localFilePath).exists()

  local bgColor, textColor = getThemeColors()

  activity.setContentView(loadlayout{
    LinearLayout, id="mainLayout", orientation=1, padding="20dp", layout_width=-1, layout_height=-1, gravity="center", backgroundColor=bgColor,
    {TextView, text=isDownloaded and "Offline Mode" or "Online Stream", textSize="14sp", layout_marginBottom="10dp", textColor=appColorStr},
    {TextView, text=surahName, textSize="26sp", typeface=Typeface.DEFAULT_BOLD, layout_marginBottom="10dp", textColor=appColorStr},
    {TextView, text="Reciter: " .. reciters[currentReciter].name, textSize="14sp", layout_marginBottom="20dp", textColor=textColor},

    {TextView, id="txtSleepTimer", text="", textSize="14sp", textColor="#E91E63", layout_marginBottom="10dp", typeface=Typeface.DEFAULT_BOLD},

    {Button, text="📖 Read Surah Text", textSize="14sp", layout_marginBottom="10dp", backgroundColor="#8E24AA", textColor=-1, onClick=function() showReadingMode(index) end},
    {Button, text="Ayat-ba-Ayat Mode", textSize="14sp", layout_marginBottom="10dp", backgroundColor="#00695C", textColor=-1, onClick=function() showAyahByAyah(index) end},
    {Button, text="Ruku Mode", textSize="14sp", layout_marginBottom="20dp", backgroundColor="#6A1B9A", textColor=-1, onClick=function() showRukuMode(index) end},

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

  btnDownload.onClick = function() if File(localFilePath).exists() then confirmDelete(localFilePath, function() showPlayer(currentIndex) end) else downloadSurah(buildQuranUrl(currentReciter, index), fileName, surahName) end end

  stopPlayer(function()
  mp = MediaPlayer() mp.setDataSource(playUrl) mp.prepareAsync()
  mp.setOnErrorListener(MediaPlayer.OnErrorListener{onError=function(p, w, e) Toast.makeText(activity, "Audio error.", 0).show() if btnPlayPause then btnPlayPause.setText("▶ " .. tr("Play")) end return true end})
  mp.setOnPreparedListener(MediaPlayer.OnPreparedListener{onPrepared=function(p)
    if Build.VERSION.SDK_INT >= 23 then p.setPlaybackParams(p.getPlaybackParams().setSpeed(playbackSpeed)) end
    skBar.setMax(p.getDuration())
    pcall(function() if p.isPlaying() then p.pause() end end) -- kabhi bhi khud-ba-khud shuru na ho, sirf tab jab user Play dabaye

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
end

function onStop()
  pcall(function() if mp and mp.isPlaying() then mp.pause() end end)
  pcall(function() if duaMp and duaMp.isPlaying() then duaMp.pause() end end)
end

function onDestroy()
  -- FIX: pehle yahan mp.stop()/mp.release() seedha (turant) call ho rahe the,
  -- jo us safe background-thread mechanism (stopPlayer) ko bypass kar dete
  -- the jo khaas is wajah se banaya gaya tha ke agar player abhi "preparing"
  -- state mein ho to seedha stop/release karna native crash de sakta hai -
  -- yehi exit karte waqt error ki wajah thi. Ab wahi safe tareeqa use hota hai.
  pcall(function() stopPlayer() end)
  pcall(function() cancelNotification() end)
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
    elseif screen == "surahlist" then showHome() return true
    elseif screen == "socialmedia" then showSettings() return true
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
showHome()