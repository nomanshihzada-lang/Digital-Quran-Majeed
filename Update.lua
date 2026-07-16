require "import"
import "android.widget.*"
import "android.view.*"
import "android.media.*"
import "android.net.*"
import "android.app.*"
import "android.os.*"
import "android.content.Intent"
import "android.net.Uri"
import "android.app.DownloadManager"
import "android.os.Environment"
import "android.content.Context"

APP_NAME = "Al Quran Majeed"
handler  = Handler()

-- Audio state
player=nil; updater=nil; currentPos=1; seekTime=10000
transPlayer=nil; translationEnabled=false; transLang="Urdu"
ayahPlayer=nil; ayahTrPlayer=nil; ayahModeOn=false; curAyah=1; ayahUpdater=nil
duaPlayer=nil; duaUpdater=nil; currentDuaPos=1
paraPlayer=nil; paraUpdater=nil; currentPara=1
paraTransEnabled=false; paraTransPlayer=nil
tafseerPlayer=nil; tafseerUpdater=nil; currentTafseerPos=1
nqPlayer=nil

-- SERVERS
URDU_BASE    = "https://archive.org/download/quran_urdu_audio_only/"
ARABIC_AYAH  = "https://everyayah.com/data/MaherAlMuaiqly128kbps/"
URDU_AYAH    = "https://everyayah.com/data/translations/urdu_shamshad_ali_khan_46kbps/"
PARA_BASE    = "https://archive.org/download/quran-juz-audio-mp3/"
PUNJABI_BASE = "https://archive.org/download/Al-Quran-with-Punjabi-Translation-Audio-MP3-CD/"
PASHTO_BASE  = "https://archive.org/download/AlQuranWithPushtoTranslationMisharyBinRashidAlafasyCD/"

reciters = {
    ["Maher Al-Muaiqly"]       = "https://server12.mp3quran.net/maher/",
    ["Mahmoud Al-Husary"]      = "https://server13.mp3quran.net/husr/",
    ["Muhammad Jibreel"]       = "https://server8.mp3quran.net/jbrl/",
    ["Ali Al-Hudhaifi"]        = "https://server9.mp3quran.net/hthfi/",
    ["Abu Bakr Al-Shatri"]     = "https://server11.mp3quran.net/shatri/",
    ["Abdul Basit"]            = "https://server7.mp3quran.net/basit/",
    ["Mishary Al-Afasy"]       = "https://server8.mp3quran.net/afs/",
    ["Saad Al-Ghamdi"]         = "https://server6.mp3quran.net/ghamdi/",
    ["Saud Al-Shuraim"]        = "https://server7.mp3quran.net/shur/",
    ["Ahmed Al-Ajmi"]          = "https://server10.mp3quran.net/ajm/",
    ["Yasser Al-Dosari"]       = "https://server11.mp3quran.net/yasser/",
    ["Abdur Rahman As-Sudais"] = "https://server11.mp3quran.net/sds/"
}
currentReciter = nil
BASE_URL = nil

surahList = {
    "Al-Fatiha","Al-Baqarah","Al-Imran","An-Nisa","Al-Ma'idah",
    "Al-An'am","Al-A'raf","Al-Anfal","At-Tawbah","Yunus",
    "Hud","Yusuf","Ar-Ra'd","Ibrahim","Al-Hijr","An-Nahl",
    "Al-Isra","Al-Kahf","Maryam","Ta-Ha","Al-Anbiya","Al-Hajj",
    "Al-Mu'minun","An-Nur","Al-Furqan","Ash-Shu'ara","An-Naml",
    "Al-Qasas","Al-Ankabut","Ar-Rum","Luqman","As-Sajda","Al-Ahzab",
    "Saba","Fatir","Ya-Sin","As-Saffat","Sad","Az-Zumar","Ghafir",
    "Fussilat","Ash-Shura","Az-Zukhruf","Ad-Dukhan","Al-Jathiya",
    "Al-Ahqaf","Muhammad","Al-Fath","Al-Hujurat","Qaf",
    "Adh-Dhariyat","At-Tur","An-Najm","Al-Qamar","Ar-Rahman",
    "Al-Waqia","Al-Hadid","Al-Mujadila","Al-Hashr","Al-Mumtahina",
    "As-Saff","Al-Jumua","Al-Munafiqun","At-Taghabun","At-Talaq",
    "At-Tahrim","Al-Mulk","Al-Qalam","Al-Haqqa","Al-Maarij",
    "Nuh","Al-Jinn","Al-Muzzammil","Al-Muddaththir","Al-Qiyama",
    "Al-Insan","Al-Mursalat","An-Naba","An-Nazi'at","Abasa",
    "At-Takwir","Al-Infitar","Al-Mutaffifin","Al-Inshiqaq","Al-Buruj",
    "At-Tariq","Al-Ala","Al-Ghashiya","Al-Fajr","Al-Balad",
    "Ash-Shams","Al-Lail","Ad-Duha","Ash-Sharh","At-Tin",
    "Al-Alaq","Al-Qadr","Al-Bayyinah","Az-Zalzalah","Al-Adiyat",
    "Al-Qaria","At-Takathur","Al-Asr","Al-Humazah","Al-Fil",
    "Quraish","Al-Ma'un","Al-Kawthar","Al-Kafirun","An-Nasr",
    "Al-Masad","Al-Ikhlas","Al-Falaq","An-Nas"
}

ayahCount = {
    7,286,200,176,120,165,206,75,129,109,
    123,111,43,52,99,128,111,110,98,135,
    112,78,118,64,77,227,93,88,69,60,
    34,30,73,54,45,83,182,88,75,85,
    54,53,89,59,37,35,38,29,18,45,
    60,49,62,55,78,96,29,22,24,13,
    14,11,11,18,12,12,30,52,52,44,
    28,28,20,56,40,31,50,40,46,42,
    29,19,36,25,22,17,19,26,30,20,
    15,21,11,8,8,19,5,8,8,11,
    11,8,3,9,5,4,7,3,6,3,5,4,5,6
}

paraNames = {
    "Alif Lam Meem","Sa-Ya-Qool","Tilkar Rusul","Lan Tanalo","Wal Mohsanat",
    "La Yuhibbullah","Wa Iza Samiu","Wa Lau Annana","Qalal Mala","Wa Alamu",
    "Yatazirun","Wa Ma Min Dabbah","Wa Ma Ubarriu","Rubama","Subhanalazi",
    "Qal Alam","Iqtaraba","Qad Aflaha","Wa Qalallazina","Aman Khalaq",
    "Utlu Ma Oohi-Ya","Wa Man Yaqnut","Wa Mali","Fa Man Azlam","Ilahe Yurad",
    "Ha-Meem","Qala Fama Khatbukum","Qad Sami-Allah","Tabarakallazi","Amma"
}

paraFirstSurah = {
    1,2,2,2,3,3,4,4,5,5,
    6,7,8,9,10,11,13,15,17,19,
    21,23,25,27,29,31,33,34,35,78
}

tafseerNames = {
    "Fatiha","Baqarah","Imran","Nisa","Maidah",
    "Anam","Araf","Anfal","Tawba","Yunus",
    "Hud","Yusuf","Raad","Ibrahim","Hijr",
    "Nahl","Isra","Kahf","Maryam","TaHa",
    "Anbiya","Hajj","Muminun","Nur","Furqan",
    "Shuara","Naml","Qasas","Ankabut","Rum",
    "Luqman","Sajda","Ahzab","Saba","Fatir",
    "Yasin","Saffat","Sad","Zumar","Ghafir",
    "Fussilat","Shura","Zukhruf","Dukhan","Jathiya",
    "Ahqaf","Muhammad","Fath","Hujurat","Qaf",
    "Dhariyat","Tur","Najm","Qamar","Rahman",
    "Waqia","Hadid","Mujadila","Hashr","Mumtahina",
    "Saff","Jumua","Munafiqun","Taghabun","Talaq",
    "Tahrim","Mulk","Qalam","Haqqa","Maarij",
    "Nuh","Jinn","Muzzammil","Muddaththir","Qiyama",
    "Insan","Mursalat","Naba","Naziat","Abasa",
    "Takwir","Infitar","Mutaffifin","Inshiqaq","Buruj",
    "Tariq","Ala","Ghashiya","Fajr","Balad",
    "Shams","Lail","Duha","Sharh","Tin",
    "Alaq","Qadr","Bayyinah","Zalzalah","Adiyat",
    "Qaria","Takasur","Asr","Humazah","Fil",
    "Quraish","Maun","Kawthar","Kafirun","Nasr",
    "Masad","Ikhlas","Falaq","Nas"
}

-- Punjabi pre-encoded filenames
punjabiFiles = {
    "001%20-%20Al-Fatihah%20(%20The%20Opening%20)",
    "002%20-%20Al-Baqarah%20(%20The%20Cow%20)",
    "003%20-%20Al-Imran%20(%20The%20Family%20of%20Imran%20)",
    "004%20-%20An-Nisa%20(%20The%20Women%20)",
    "005%20-%20Al-Maidah%20(%20The%20Table%20spread%20with%20Food%20)",
    "006%20-%20Al-An%27am%20(%20The%20Cattle%20)",
    "007%20-%20Al-A%27raf%20(The%20Heights%20)",
    "008%20-%20Al-Anfal%20(%20The%20Spoils%20of%20War%20)",
    "009%20-%20At-Taubah%20(%20The%20Repentance%20)",
    "010%20-%20Yunus%20(%20Jonah%20)",
    "011%20-%20Hud","012%20-%20Yusuf%20(Joseph%20)",
    "013%20-%20Ar-Ra%27d","014%20-%20Ibrahim",
    "015%20-%20Al-Hijr","016%20-%20An-Nahl",
    "017%20-%20Al-Isra","018%20-%20Al-Kahf",
    "019%20-%20Maryam","020%20-%20Ta-Ha",
    "021%20-%20Al-Anbiya","022%20-%20Al-Hajj",
    "023%20-%20Al-Muminun","024%20-%20An-Nur",
    "025%20-%20Al-Furqan","026%20-%20Ash-Shuara",
    "027%20-%20An-Naml","028%20-%20Al-Qasas",
    "029%20-%20Al-Ankabut","030%20-%20Ar-Rum",
    "031%20-%20Luqman","032%20-%20As-Sajda",
    "033%20-%20Al-Ahzab","034%20-%20Saba",
    "035%20-%20Fatir","036%20-%20Ya-Seen",
    "037%20-%20As-Saffat","038%20-%20Sad",
    "039%20-%20Az-Zumar","040%20-%20Ghafir",
    "041%20-%20Fussilat","042%20-%20Ash-Shura",
    "043%20-%20Az-Zukhruf","044%20-%20Ad-Dukhan",
    "045%20-%20Al-Jathiya","046%20-%20Al-Ahqaf",
    "047%20-%20Muhammad","048%20-%20Al-Fath",
    "049%20-%20Al-Hujurat","050%20-%20Qaf",
    "051%20-%20Adh-Dhariyat","052%20-%20At-Tur",
    "053%20-%20An-Najm","054%20-%20Al-Qamar",
    "055%20-%20Ar-Rahman","056%20-%20Al-Waqia",
    "057%20-%20Al-Hadid","058%20-%20Al-Mujadila",
    "059%20-%20Al-Hashr","060%20-%20Al-Mumtahina",
    "061%20-%20As-Saff","062%20-%20Al-Jumua",
    "063%20-%20Al-Munafiqun","064%20-%20At-Taghabun",
    "065%20-%20At-Talaq","066%20-%20At-Tahrim",
    "067%20-%20Al-Mulk","068%20-%20Al-Qalam",
    "069%20-%20Al-Haqqa","070%20-%20Al-Maarij",
    "071%20-%20Nuh","072%20-%20Al-Jinn",
    "073%20-%20Al-Muzzammil","074%20-%20Al-Muddaththir",
    "075%20-%20Al-Qiyama","076%20-%20Al-Insan",
    "077%20-%20Al-Mursalat","078%20-%20An-Naba",
    "079%20-%20An-Naziat","080%20-%20Abasa",
    "081%20-%20At-Takwir","082%20-%20Al-Infitar",
    "083%20-%20Al-Mutaffifin","084%20-%20Al-Inshiqaq",
    "085%20-%20Al-Buruj","086%20-%20At-Tariq",
    "087%20-%20Al-Ala","088%20-%20Al-Ghashiya",
    "089%20-%20Al-Fajr","090%20-%20Al-Balad",
    "091%20-%20Ash-Shams","092%20-%20Al-Lail",
    "093%20-%20Ad-Duha","094%20-%20Ash-Sharh",
    "095%20-%20At-Tin","096%20-%20Al-Alaq",
    "097%20-%20Al-Qadr","098%20-%20Al-Bayyinah",
    "099%20-%20Az-Zalzalah","100%20-%20Al-Adiyat",
    "101%20-%20Al-Qaria","102%20-%20At-Takathur",
    "103%20-%20Al-Asr","104%20-%20Al-Humazah",
    "105%20-%20Al-Fil","106%20-%20Quraish",
    "107%20-%20Al-Maun","108%20-%20Al-Kawthar",
    "109%20-%20Al-Kafirun","110%20-%20An-Nasr",
    "111%20-%20Al-Masad","112%20-%20Al-Ikhlas",
    "113%20-%20Al-Falaq","114%20-%20An-Nas"
}

-- Pashto: "01 Al Fatiha.mp3" format
pashtoShort = {
    "Al Fatiha","Al Baqara","Ale Imran","An Nisa","Al Maeda",
    "Al Anaam","Al Araaf","Al Anfal","At Tawba","Yunus",
    "Hud","Yusuf","Ar Raad","Ibrahim","Al Hijr",
    "An Nahl","Al Isra","Al Kahf","Maryam","Ta Ha",
    "Al Anbiya","Al Hajj","Al Muminun","An Nur","Al Furqan",
    "Ash Shuara","An Naml","Al Qasas","Al Ankabut","Ar Rum",
    "Luqman","As Sajda","Al Ahzab","Saba","Fatir",
    "Ya Sin","As Saffat","Sad","Az Zumar","Ghafir",
    "Fussilat","Ash Shura","Az Zukhruf","Ad Dukhan","Al Jathiya",
    "Al Ahqaf","Muhammad","Al Fath","Al Hujurat","Qaf",
    "Adh Dhariyat","At Tur","An Najm","Al Qamar","Ar Rahman",
    "Al Waqia","Al Hadid","Al Mujadila","Al Hashr","Al Mumtahina",
    "As Saff","Al Jumua","Al Munafiqun","At Taghabun","At Talaq",
    "At Tahrim","Al Mulk","Al Qalam","Al Haqqa","Al Maarij",
    "Nuh","Al Jinn","Al Muzzammil","Al Muddaththir","Al Qiyama",
    "Al Insan","Al Mursalat","An Naba","An Naziat","Abasa",
    "At Takwir","Al Infitar","Al Mutaffifin","Al Inshiqaq","Al Buruj",
    "At Tariq","Al Ala","Al Ghashiya","Al Fajr","Al Balad",
    "Ash Shams","Al Lail","Ad Duha","Ash Sharh","At Tin",
    "Al Alaq","Al Qadr","Al Bayyinah","Az Zalzalah","Al Adiyat",
    "Al Qaria","At Takathur","Al Asr","Al Humazah","Al Fil",
    "Quraish","Al Maun","Al Kawthar","Al Kafirun","An Nasr",
    "Al Masad","Al Ikhlas","Al Falaq","An Nas"
}

-- Noorani Qaida 29 letters
noorani = {
    {"丕","丕賱賮","Alif"},{"亘","亘蹝","Ba"},{"鬲","鬲蹝","Ta"},{"孬","孬蹝","Tha"},
    {"噩","噩蹖賲","Jeem"},{"丨","丨蹝","Ha"},{"禺","禺蹝","Kha"},{"丿","丿丕賱","Dal"},
    {"匕","匕丕賱","Dhal"},{"乇","乇蹝","Ra"},{"夭","夭蹝","Zay"},{"爻","爻蹖賳","Sin"},
    {"卮","卮蹖賳","Shin"},{"氐","氐丕丿","Saad"},{"囟","囟丕丿","Daad"},{"胤","胤賵蹝","Taa"},
    {"馗","馗賵蹝","Dhaa"},{"毓","毓蹖賳","Ain"},{"睾","睾蹖賳","Ghain"},{"賮","賮蹝","Fa"},
    {"賯","賯丕賮","Qaaf"},{"讴","讴丕賮","Kaaf"},{"賱","賱丕賲","Laam"},{"賲","賲蹖賲","Meem"},
    {"賳","賳賵賳","Noon"},{"賵","賵丕丐","Waaw"},{"蹃","蹃蹝","Ha"},{"亍","蹃賲夭蹃","Hamza"},
    {"蹖","蹖蹝","Ya"}
}
-- Each letter maps to a short surah for audio
nqSurahMap = {
    112,113,114,112,111,110,109,108,107,106,
    105,104,103,102,101,100,99,98,97,96,
    95,94,93,92,91,90,89,88,87
}

-- Duas list
local DB = "https://archive.org/download/HisnulMuslimAudio_201510/"
duaList = {
    {name="馃げ Dua Before Eating",   arabic="亘賽爻賿賲賽 丕賱賱賻賾賴賽",                              urdu="Allah ke naam se",                      audio=DB.."n36.mp3"},
    {name="馃げ Dua After Eating",    arabic="丕賱賿丨賻賲賿丿購 賱賽賱賻賾賴賽 丕賱賻賾匕賽賷 兀賻胤賿毓賻賲賻賳賽賷",       urdu="Sab tareef Allah ke liye",              audio=DB.."n38.mp3"},
    {name="馃げ Dua Before Sleeping", arabic="亘賽丕爻賿賲賽賰賻 丕賱賱賻賾賴購賲賻賾 兀賻賲購賵鬲購 賵賻兀賻丨賿賷賻丕",     urdu="Tere naam se marta aur jee uthta hoon", audio=DB.."n22.mp3"},
    {name="馃げ Dua After Waking",    arabic="丕賱賿丨賻賲賿丿購 賱賽賱賻賾賴賽 丕賱賻賾匕賽賷 兀賻丨賿賷賻丕賳賻丕",       urdu="Sab tareef jis ne zinda kiya",          audio=DB.."n1.mp3"},
    {name="馃げ Entering Masjid",     arabic="丕賱賱賻賾賴購賲賻賾 丕賮賿鬲賻丨賿 賱賽賷 兀賻亘賿賵賻丕亘賻 乇賻丨賿賲賻鬲賽賰賻", urdu="Rehmat ke darwaaze khol de",            audio=DB.."n43.mp3"},
    {name="馃げ Leaving Masjid",      arabic="丕賱賱賻賾賴購賲賻賾 廿賽賳賽賾賷 兀賻爻賿兀賻賱購賰賻 賲賽賳賿 賮賻囟賿賱賽賰賻",  urdu="Tujh se tera fazal maangta hoon",       audio=DB.."n44.mp3"},
    {name="馃げ Entering Home",       arabic="丕賱賱賻賾賴購賲賻賾 禺賻賷賿乇賻 丕賱賿賲賻賵賿賱賻噩賽",               urdu="Ghar mein daakhil hone ka khair",       audio=DB.."n15.mp3"},
    {name="馃げ Leaving Home",        arabic="亘賽爻賿賲賽 丕賱賱賻賾賴賽 鬲賻賵賻賰賻賾賱賿鬲購 毓賻賱賻賶 丕賱賱賻賾賴賽",   urdu="Allah par bharosa karta hoon",          audio=DB.."n16.mp3"},
    {name="馃げ Dua for Parents",     arabic="乇賻亘賽賾 丕乇賿丨賻賲賿賴購賲賻丕",                           urdu="Un par rehmat farma",                   audio=DB.."n103.mp3"},
    {name="馃げ Dua Traveling",       arabic="爻購亘賿丨賻丕賳賻 丕賱賻賾匕賽賷 爻賻禺賻賾乇賻 賱賻賳賻丕 賴賻匕賻丕",       urdu="Paak hai jis ne qaadir kiya",           audio=DB.."n82.mp3"},
    {name="馃げ Dua for Anxiety",     arabic="丕賱賱賻賾賴購賲賻賾 兀賻毓購賵匕購 亘賽賰賻 賲賽賳賻 丕賱賿賴賻賲賽賾",       urdu="Fikar aur gham se teri panaah",         audio=DB.."n48.mp3"},
    {name="馃げ Dua Forgiveness",     arabic="乇賻亘賽賾 丕睾賿賮賽乇賿 賱賽賷 賵賻鬲購亘賿 毓賻賱賻賷賻賾",            urdu="Maaf farma aur tawbah qabool farma",    audio=DB.."n20.mp3"},
    {name="馃摽 Morning Adhkar",      arabic="兀賻氐賿亘賻丨賿賳賻丕 賵賻兀賻氐賿亘賻丨賻 丕賱賿賲購賱賿賰購 賱賽賱賻賾賴賽",    urdu="Subah hui aur saltanat Allah ke liye",  audio=DB.."n4.mp3"},
    {name="馃摽 Evening Adhkar",      arabic="兀賻賲賿爻賻賷賿賳賻丕 賵賻兀賻賲賿爻賻賶 丕賱賿賲購賱賿賰購 賱賽賱賻賾賴賽",     urdu="Shaam hui aur saltanat Allah ke liye",  audio=DB.."n19.mp3"},
    {name="馃摽 Ayatul Kursi",        arabic="丕賱賱賻賾賴購 賱賻丕 廿賽賱賻賴賻 廿賽賱賻賾丕 賴購賵賻",               urdu="Allah ke siwa koi ilah nahi",           audio=DB.."n25.mp3"},
    {name="馃摽 Tasbeeh Fatima",      arabic="爻購亘賿丨賻丕賳賻 丕賱賱賻賾賴賽 賵賻亘賽丨賻賲賿丿賽賴賽",              urdu="Allah paak hai uski taarif hai",        audio=DB.."n26.mp3"},
    {name="馃げ Before Wudu",         arabic="亘賽爻賿賲賽 丕賱賱賻賾賴賽",                              urdu="Allah ke naam se wudu shuru",           audio=DB.."n39.mp3"},
    {name="馃げ After Wudu",          arabic="兀賻卮賿賴賻丿購 兀賻賳賿 賱賻丕 廿賽賱賻賴賻 廿賽賱賻賾丕 丕賱賱賻賾賴購",    urdu="Allah ke siwa koi ilah nahi",           audio=DB.."n40.mp3"}
}

-----------------------------------------------------------------
-- UTILS
-----------------------------------------------------------------
function ft(ms)
    local s = math.floor(ms / 1000)
    return string.format("%02d:%02d", math.floor(s/60), s%60)
end

function isConn()
    local ni = activity.getSystemService("connectivity").getActiveNetworkInfo()
    return ni and ni.isConnected()
end

function aa(mp)
    if Build.VERSION.SDK_INT >= 21 then
        mp.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build()
        )
    else
        mp.setAudioStreamType(AudioManager.STREAM_MUSIC)
    end
end

function getLocalUrl(filename)
    local ok, result = pcall(function()
        local dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        local f = luajava.newInstance("java.io.File", dir, filename)
        if f.exists() and f.length() > 500 then
            return "file://" .. f.getAbsolutePath()
        end
        return nil
    end)
    if ok then return result end
    return nil
end

function smartUrl(onlineUrl, filename)
    local loc = getLocalUrl(filename)
    if loc then return loc end
    if isConn() then return onlineUrl end
    return nil
end

function newMP(url, cbReady, cbDone, cbErr)
    local mp = MediaPlayer()
    aa(mp)
    mp.setOnPreparedListener({
        onPrepared = function(m)
            cbReady(m)
        end
    })
    mp.setOnCompletionListener({
        onCompletion = function(m)
            if cbDone then cbDone(m) end
        end
    })
    mp.setOnErrorListener({
        onError = function(m, w, e)
            if cbErr then cbErr() end
            return true
        end
    })
    pcall(function()
        mp.setDataSource(activity, Uri.parse(url))
        mp.prepareAsync()
    end)
    return mp
end

function stopMP(mp)
    if mp then
        pcall(function()
            if mp.isPlaying() then mp.stop() end
            mp.release()
        end)
    end
    return nil
end

function dlFile(url, title, fname)
    pcall(function()
        local dm = activity.getSystemService(Context.DOWNLOAD_SERVICE)
        local req = DownloadManager.Request(Uri.parse(url))
        req.setTitle(title)
        req.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, fname)
        req.setNotificationVisibility(
            DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED
        )
        dm.enqueue(req)
        Toast.makeText(activity, "Downloading: " .. title, 0).show()
    end)
end

function mkUpdater(getMP, getSeek, getCur)
    local r
    r = Runnable({
        run = function()
            local mp = getMP()
            if mp then
                local ok, playing = pcall(function() return mp.isPlaying() end)
                if ok and playing then
                    pcall(function()
                        local p = mp.getCurrentPosition()
                        getSeek().setProgress(p)
                        getCur().setText(ft(p))
                    end)
                    handler.postDelayed(r, 1000)
                end
            end
        end
    })
    return r
end

function transUrl(n)
    if transLang == "Urdu" then
        return URDU_BASE .. string.format("%03d", n) .. ".mp3",
               "UrduTarjuma_" .. n .. ".mp3"
    elseif transLang == "Punjabi" then
        return PUNJABI_BASE .. punjabiFiles[n] .. ".mp3",
               "Punjabi_" .. n .. ".mp3"
    else
        local nn = n < 10 and ("0" .. n) or tostring(n)
        local enc = pashtoShort[n]:gsub(" ", "%%20")
        return PASHTO_BASE .. nn .. "%20" .. enc .. ".ogg",
               "Pashto_" .. n .. ".ogg"
    end
end

-----------------------------------------------------------------
-- STOP ALL
-----------------------------------------------------------------
function stopAll()
    if updater        then handler.removeCallbacks(updater)        end
    if ayahUpdater    then handler.removeCallbacks(ayahUpdater)    end
    if duaUpdater     then handler.removeCallbacks(duaUpdater)     end
    if paraUpdater    then handler.removeCallbacks(paraUpdater)    end
    if tafseerUpdater then handler.removeCallbacks(tafseerUpdater) end
    player         = stopMP(player)
    transPlayer    = stopMP(transPlayer)
    ayahPlayer     = stopMP(ayahPlayer)
    ayahTrPlayer   = stopMP(ayahTrPlayer)
    duaPlayer      = stopMP(duaPlayer)
    paraPlayer     = stopMP(paraPlayer)
    paraTransPlayer = stopMP(paraTransPlayer)
    tafseerPlayer  = stopMP(tafseerPlayer)
    nqPlayer       = stopMP(nqPlayer)
    ayahModeOn     = false
    updater        = nil
    ayahUpdater    = nil
    duaUpdater     = nil
    paraUpdater    = nil
    tafseerUpdater = nil
end

-----------------------------------------------------------------
-- SURAH PLAYER
-----------------------------------------------------------------
function playSurahTrans(n)
    transPlayer = stopMP(transPlayer)
    local url, fname = transUrl(n)
    local fu = smartUrl(url, fname)
    if not fu then
        if n < 114 then playSurah(n + 1) end
        return
    end
    transPlayer = newMP(
        fu,
        function(mp) mp.start() end,
        function(mp)
            transPlayer = stopMP(transPlayer)
            if translationEnabled and n < 114 then
                playSurah(n + 1)
            end
        end,
        function()
            transPlayer = stopMP(transPlayer)
            if n < 114 then playSurah(n + 1) end
        end
    )
end

function playSurah(pos)
    if not currentReciter then
        Toast.makeText(activity, "Pehle Reciter select karein 鈥� Settings se", 0).show()
        return
    end
    local fname = "Arabic_" .. pos .. ".mp3"
    local url   = BASE_URL .. string.format("%03d", pos) .. ".mp3"
    local fu    = smartUrl(url, fname)
    if not fu then
        Toast.makeText(activity, "Internet nahi. Pehle download karein: " .. surahList[pos], 0).show()
        return
    end
    if updater then handler.removeCallbacks(updater) end
    player       = stopMP(player)
    transPlayer  = stopMP(transPlayer)
    currentPos   = pos
    ayahModeOn   = false
    pcall(function()
        seekBar.setProgress(0)
        currentTxt.setText("00:00")
        totalTxt.setText("00:00")
        playBtn.setText("Loading...")
        nowPlayingTxt.setText(surahList[pos])
    end)
    player = newMP(
        fu,
        function(mp)
            local d = mp.getDuration()
            if d and d > 0 then
                pcall(function()
                    seekBar.setMax(d)
                    totalTxt.setText(ft(d))
                end)
            end
            mp.start()
            updater = mkUpdater(
                function() return player end,
                function() return seekBar end,
                function() return currentTxt end
            )
            handler.post(updater)
            pcall(function() playBtn.setText("Pause") end)
        end,
        function(mp)
            player = stopMP(player)
            if translationEnabled then
                playSurahTrans(currentPos)
            elseif currentPos < 114 then
                playSurah(currentPos + 1)
            end
        end,
        function()
            player = stopMP(player)
            pcall(function() playBtn.setText("Play") end)
            Toast.makeText(activity, "Error: " .. surahList[pos], 0).show()
        end
    )
end

-----------------------------------------------------------------
-- AYAH MODE
-----------------------------------------------------------------
function advAyah(s, a)
    if not ayahModeOn then return end
    local mx = ayahCount[s] or 1
    if a < mx then
        playAyahAt(s, a + 1)
    elseif s < 114 then
        playAyahAt(s + 1, 1)
    else
        ayahModeOn = false
        pcall(function()
            ayahModeBtn.setText("馃帶 Ayat Mode: OFF")
            ayahModeBtn.setBackgroundColor(0xFF607D8B)
        end)
        Toast.makeText(activity, "Quran Majeed mukammal hua 鈥� MashaAllah!", 0).show()
    end
end

function playAyahTrans(s, a)
    ayahTrPlayer = stopMP(ayahTrPlayer)
    local key   = string.format("%03d%03d", s, a)
    local url   = URDU_AYAH .. key .. ".mp3"
    local fname = "AyahTrans_" .. key .. ".mp3"
    local fu    = smartUrl(url, fname)
    if not fu then
        advAyah(s, a)
        return
    end
    ayahTrPlayer = newMP(
        fu,
        function(mp) mp.start() end,
        function(mp)
            ayahTrPlayer = stopMP(ayahTrPlayer)
            advAyah(s, a)
        end,
        function()
            ayahTrPlayer = stopMP(ayahTrPlayer)
            advAyah(s, a)
        end
    )
end

function playAyahAt(s, a)
    if ayahUpdater then handler.removeCallbacks(ayahUpdater) end
    ayahPlayer   = stopMP(ayahPlayer)
    ayahTrPlayer = stopMP(ayahTrPlayer)
    currentPos   = s
    curAyah      = a
    local key    = string.format("%03d%03d", s, a)
    local url    = ARABIC_AYAH .. key .. ".mp3"
    local fname  = "Ayah_" .. key .. ".mp3"
    local fu     = smartUrl(url, fname)
    if not fu then
        Toast.makeText(activity, "Internet nahi. Pehle ayah download karein.", 0).show()
        return
    end
    ayahPlayer = newMP(
        fu,
        function(mp)
            local d = mp.getDuration()
            if d and d > 0 then
                pcall(function()
                    seekBar.setMax(d)
                    totalTxt.setText(ft(d))
                end)
            end
            mp.start()
            ayahUpdater = mkUpdater(
                function() return ayahPlayer end,
                function() return seekBar end,
                function() return currentTxt end
            )
            handler.post(ayahUpdater)
            pcall(function()
                nowPlayingTxt.setText(
                    surahList[s] .. " 鈥� Ayah " .. a .. "/" .. (ayahCount[s] or "?")
                )
                playBtn.setText("Pause")
            end)
        end,
        function(mp)
            if ayahUpdater then handler.removeCallbacks(ayahUpdater) end
            ayahPlayer = stopMP(ayahPlayer)
            playAyahTrans(s, a)
        end,
        function()
            ayahPlayer = stopMP(ayahPlayer)
            advAyah(s, a)
        end
    )
end

-----------------------------------------------------------------
-- DUA PLAYER
-----------------------------------------------------------------
function playDuaAt(pos)
    if pos < 1 or pos > #duaList then return end
    currentDuaPos = pos
    if duaUpdater then handler.removeCallbacks(duaUpdater) end
    duaPlayer = stopMP(duaPlayer)
    local d = duaList[pos]
    pcall(function()
        duaNowPlayingTxt.setText(pos .. ". " .. d.name)
        duaArabicTxt.setText(d.arabic)
        duaUrduTxt.setText(d.urdu)
        duaSeekBar.setProgress(0)
        duaCurrentTxt.setText("00:00")
        duaTotalTxt.setText("00:00")
        duaPlayBtn.setText("Loading...")
    end)
    local fname = "Dua_" .. pos .. ".mp3"
    local fu    = smartUrl(d.audio, fname)
    if not fu then
        pcall(function() duaPlayBtn.setText("鈻� Play") end)
        Toast.makeText(activity, "Internet nahi. Pehle download karein.", 0).show()
        return
    end
    duaPlayer = newMP(
        fu,
        function(mp)
            local dur = mp.getDuration()
            if dur and dur > 0 then
                pcall(function()
                    duaSeekBar.setMax(dur)
                    duaTotalTxt.setText(ft(dur))
                end)
            end
            mp.start()
            duaUpdater = mkUpdater(
                function() return duaPlayer end,
                function() return duaSeekBar end,
                function() return duaCurrentTxt end
            )
            handler.post(duaUpdater)
            pcall(function() duaPlayBtn.setText("鈴� Pause") end)
        end,
        function(mp)
            duaPlayer = stopMP(duaPlayer)
            pcall(function()
                duaSeekBar.setProgress(0)
                duaCurrentTxt.setText("00:00")
                duaPlayBtn.setText("鈻� Play")
            end)
            if currentDuaPos < #duaList then
                handler.postDelayed(
                    Runnable({ run = function() playDuaAt(currentDuaPos + 1) end }),
                    600
                )
            end
        end,
        function()
            duaPlayer = stopMP(duaPlayer)
            pcall(function() duaPlayBtn.setText("鈻� Play") end)
            Toast.makeText(activity, "Dua load nahi hui. Internet check karein.", 0).show()
        end
    )
end

-----------------------------------------------------------------
-- PARA PLAYER
-----------------------------------------------------------------
function playParaTrans(n)
    paraTransPlayer = stopMP(paraTransPlayer)
    local firstS    = paraFirstSurah[n] or 1
    local url, fname = transUrl(firstS)
    local fu        = smartUrl(url, "ParaTrans_" .. n .. "_" .. fname)
    if not fu then return end
    paraTransPlayer = newMP(
        fu,
        function(mp) mp.start() end,
        function(mp)
            paraTransPlayer = stopMP(paraTransPlayer)
            if paraTransEnabled and currentPara < 30 then
                playPara(currentPara + 1)
            end
        end,
        function()
            paraTransPlayer = stopMP(paraTransPlayer)
        end
    )
end

function playPara(n)
    if paraUpdater then handler.removeCallbacks(paraUpdater) end
    paraPlayer      = stopMP(paraPlayer)
    paraTransPlayer = stopMP(paraTransPlayer)
    currentPara     = n
    local nn   = n < 10 and ("0" .. n) or tostring(n)
    local url  = PARA_BASE .. "Para%20" .. nn .. ".mp3"
    local fname = "Para_" .. n .. ".mp3"
    local fu   = smartUrl(url, fname)
    if not fu then
        Toast.makeText(activity, "Internet nahi. Pehle Para " .. n .. " download karein.", 0).show()
        return
    end
    pcall(function()
        paraSeekBar.setProgress(0)
        paraCurrentTxt.setText("00:00")
        paraTotalTxt.setText("00:00")
        paraPlayBtn.setText("Loading...")
        paraTitleTxt.setText("Para " .. n .. ": " .. paraNames[n])
    end)
    paraPlayer = newMP(
        fu,
        function(mp)
            local dur = mp.getDuration()
            if dur and dur > 0 then
                pcall(function()
                    paraSeekBar.setMax(dur)
                    paraTotalTxt.setText(ft(dur))
                end)
            end
            mp.start()
            paraUpdater = mkUpdater(
                function() return paraPlayer end,
                function() return paraSeekBar end,
                function() return paraCurrentTxt end
            )
            handler.post(paraUpdater)
            pcall(function() paraPlayBtn.setText("鈴� Pause") end)
        end,
        function(mp)
            paraPlayer = stopMP(paraPlayer)
            pcall(function() paraPlayBtn.setText("鈻� Play") end)
            if paraTransEnabled then
                playParaTrans(currentPara)
            elseif currentPara < 30 then
                playPara(currentPara + 1)
            end
        end,
        function()
            paraPlayer = stopMP(paraPlayer)
            pcall(function() paraPlayBtn.setText("鈻� Play") end)
            Toast.makeText(activity, "Para load nahi hua.", 0).show()
        end
    )
end

-----------------------------------------------------------------
-- TAFSEER PLAYER
-----------------------------------------------------------------
function playTafseer(pos)
    if tafseerUpdater then handler.removeCallbacks(tafseerUpdater) end
    tafseerPlayer     = stopMP(tafseerPlayer)
    currentTafseerPos = pos
    local nm   = tafseerNames[pos]
    local url  = "https://archive.org/download/" .. pos .. "." .. nm
                 .. "/" .. pos .. "." .. nm .. ".mp3"
    local fname = "Tafseer_" .. pos .. ".mp3"
    local fu   = smartUrl(url, fname)
    if not fu then
        Toast.makeText(activity, "Internet nahi. Pehle download karein.", 0).show()
        return
    end
    pcall(function()
        tafSeekBar.setProgress(0)
        tafCurrentTxt.setText("00:00")
        tafTotalTxt.setText("00:00")
        tafPlayBtn.setText("Loading...")
        tafTitleTxt.setText("Tafseer: " .. surahList[pos])
    end)
    tafseerPlayer = newMP(
        fu,
        function(mp)
            local dur = mp.getDuration()
            if dur and dur > 0 then
                pcall(function()
                    tafSeekBar.setMax(dur)
                    tafTotalTxt.setText(ft(dur))
                end)
            end
            mp.start()
            tafseerUpdater = mkUpdater(
                function() return tafseerPlayer end,
                function() return tafSeekBar end,
                function() return tafCurrentTxt end
            )
            handler.post(tafseerUpdater)
            pcall(function() tafPlayBtn.setText("鈴� Pause") end)
        end,
        function(mp)
            tafseerPlayer = stopMP(tafseerPlayer)
            pcall(function() tafPlayBtn.setText("鈻� Play") end)
        end,
        function()
            tafseerPlayer = stopMP(tafseerPlayer)
            pcall(function() tafPlayBtn.setText("鈻� Play") end)
            Toast.makeText(activity, "Tafseer load nahi hua. Internet check karein.", 0).show()
        end
    )
end

-----------------------------------------------------------------
-- MENUS
-----------------------------------------------------------------
function showReciterList()
    local names = {}
    for k in pairs(reciters) do table.insert(names, k) end
    table.sort(names)
    local dlg = AlertDialog.Builder(activity)
        .setTitle("馃帣 Reciter Select (Long press = URL Edit)")
        .setItems(names, {
            onClick = function(d, w)
                currentReciter = names[w + 1]
                BASE_URL = reciters[currentReciter]
                Toast.makeText(activity, "Reciter: " .. currentReciter, 0).show()
            end
        })
        .show()
    local lv = dlg.getListView()
    if lv then
        lv.setOnItemLongClickListener({
            onItemLongClick = function(p, v, pos, id)
                local nm  = names[pos + 1]
                local inp = EditText(activity)
                inp.setText(reciters[nm])
                AlertDialog.Builder(activity)
                    .setTitle("Edit URL: " .. nm)
                    .setView(inp)
                    .setPositiveButton("Save", {
                        onClick = function()
                            local nv = inp.getText().toString()
                            if nv ~= "" then
                                reciters[nm] = nv
                                if currentReciter == nm then BASE_URL = nv end
                                Toast.makeText(activity, "Saved!", 0).show()
                            end
                        end
                    })
                    .setNegativeButton("Cancel", nil)
                    .show()
                dlg.dismiss()
                return true
            end
        })
    end
end

function showTransLangMenu()
    AlertDialog.Builder(activity)
        .setTitle("馃寪 Tarjuma Zaban")
        .setItems(
            {"馃嚨馃嚢 Urdu (Jalandhari)", "馃嚨馃嚢 Punjabi (Khushi Muhammad)", "馃嚘馃嚝 Pashto (Mishary)"},
            {
                onClick = function(d, w)
                    local langs = {"Urdu", "Punjabi", "Pashto"}
                    transLang = langs[w + 1]
                    Toast.makeText(activity, "Tarjuma: " .. transLang, 0).show()
                end
            }
        )
        .show()
end

function showSpeedMenu(tgt)
    local sp = {"0.5x", "1.0x", "1.25x", "1.5x", "1.75x", "2.0x"}
    AlertDialog.Builder(activity)
        .setTitle("鈴� Playback Speed")
        .setItems(sp, {
            onClick = function(d, w)
                if tgt and Build.VERSION.SDK_INT >= 23 then
                    pcall(function()
                        local vv = {0.5, 1.0, 1.25, 1.5, 1.75, 2.0}
                        local pp = tgt.getPlaybackParams()
                        pp.setSpeed(vv[w + 1])
                        tgt.setPlaybackParams(pp)
                        Toast.makeText(activity, "Speed: " .. sp[w + 1], 0).show()
                    end)
                else
                    Toast.makeText(activity, "SDK 23+ required", 0).show()
                end
            end
        })
        .show()
end

function showSeekMenu()
    local opts = {"5s", "10s", "15s", "20s", "25s", "30s"}
    local vals = {5000, 10000, 15000, 20000, 25000, 30000}
    AlertDialog.Builder(activity)
        .setTitle("鈴� Seek Jump Time")
        .setItems(opts, {
            onClick = function(d, w)
                seekTime = vals[w + 1]
                pcall(function()
                    rwdBtn.setText("鈼€ " .. opts[w + 1])
                    fwdBtn.setText(opts[w + 1] .. " 鈻�")
                end)
            end
        })
        .show()
end

-----------------------------------------------------------------
-- SCREEN: HOME
-----------------------------------------------------------------
function showHomeScreen()
    stopAll()
    activity.setContentView(loadlayout({
        LinearLayout, orientation = "vertical",
        layout_width = "fill", layout_height = "fill",
        {
            TextView, text = "馃摉 Al Quran Majeed",
            textSize = "22sp", gravity = "center",
            padding = "14dp", textColor = "#1B5E20", typeface = 1,
            layout_width = "fill", layout_height = "wrap_content"
        },
        {
            TextView,
            text = "Developer: Sabir Jamil | Tech For V I",
            textSize = "11sp", gravity = "center",
            textColor = "#888888",
            layout_width = "fill", layout_height = "wrap_content"
        },
        {
            LinearLayout, orientation = "horizontal",
            layout_width = "fill", layout_height = "0", layout_weight = "1",
            {
                Button, id = "btnSurah", text = "馃晫\n114 Surahs",
                layout_width = "0", layout_weight = "1",
                layout_height = "fill", layout_margin = "4dp"
            },
            {
                Button, id = "btnPara", text = "馃摎\n30 Paare",
                layout_width = "0", layout_weight = "1",
                layout_height = "fill", layout_margin = "4dp"
            }
        },
        {
            LinearLayout, orientation = "horizontal",
            layout_width = "fill", layout_height = "0", layout_weight = "1",
            {
                Button, id = "btnDua", text = "馃げ\nDuaein",
                layout_width = "0", layout_weight = "1",
                layout_height = "fill", layout_margin = "4dp"
            },
            {
                Button, id = "btnTafseer", text = "馃摐\nTafseer\nIbn Kaseer",
                layout_width = "0", layout_weight = "1",
                layout_height = "fill", layout_margin = "4dp"
            }
        },
        {
            LinearLayout, orientation = "horizontal",
            layout_width = "fill", layout_height = "0", layout_weight = "1",
            {
                Button, id = "btnQaida", text = "馃摽\nNoorani\nQaida",
                layout_width = "0", layout_weight = "1",
                layout_height = "fill", layout_margin = "4dp"
            },
            {
                Button, id = "btnSettings", text = "鈿橽nSettings",
                layout_width = "0", layout_weight = "1",
                layout_height = "fill", layout_margin = "4dp"
            }
        }
    }))

    btnSurah.setAllCaps(false)
    btnPara.setAllCaps(false)
    btnDua.setAllCaps(false)
    btnTafseer.setAllCaps(false)
    btnQaida.setAllCaps(false)
    btnSettings.setAllCaps(false)

    btnSurah.onClick    = function() showSurahListScreen() end
    btnPara.onClick     = function() showParaScreen() end
    btnDua.onClick      = function() showDuaListScreen() end
    btnTafseer.onClick  = function() showTafseerListScreen() end
    btnQaida.onClick    = function() showNooraniScreen() end
    btnSettings.onClick = function()
        AlertDialog.Builder(activity)
            .setTitle("鈿� Settings")
            .setItems({"馃帣 Reciter Select", "馃寪 Tarjuma Zaban"}, {
                onClick = function(d, w)
                    if w == 0 then
                        showReciterList()
                    else
                        showTransLangMenu()
                    end
                end
            })
            .show()
    end
end

-----------------------------------------------------------------
-- SCREEN: SURAH LIST
-----------------------------------------------------------------
function showSurahListScreen()
    activity.setContentView(loadlayout({
        LinearLayout, orientation = "vertical",
        layout_width = "fill", layout_height = "fill",
        {
            LinearLayout, orientation = "horizontal",
            layout_width = "fill", layout_height = "wrap_content",
            padding = "6dp",
            {
                TextView, text = "馃摉 114 Surahs",
                textSize = "17sp", typeface = 1,
                layout_weight = "1", gravity = "center_vertical"
            },
            { Button, id = "slBackBtn", text = "猬� Home", layout_width = "wrap_content" }
        },
        { ListView, id = "surahLv", layout_width = "fill", layout_height = "fill" }
    }))
    slBackBtn.setAllCaps(false)
    slBackBtn.onClick = function() showHomeScreen() end

    surahLv.setAdapter(
        ArrayAdapter(activity, android.R.layout.simple_list_item_1, surahList)
    )
    surahLv.onItemClick = function(p, v, pos, id)
        if not currentReciter then
            Toast.makeText(activity, "Settings se Reciter select karein", 0).show()
            return
        end
        showPlayerScreen(pos + 1)
    end
    surahLv.onItemLongClick = function(parent, view, pos, id)
        if not currentReciter then return true end
        AlertDialog.Builder(activity)
            .setTitle(surahList[pos + 1])
            .setItems(
                {"鈻� Play", "猬� Arabic DL", "猬� Tarjuma DL", "馃摐 Tafseer"},
                {
                    onClick = function(d, w)
                        if w == 0 then
                            showPlayerScreen(pos + 1)
                        elseif w == 1 then
                            dlFile(
                                BASE_URL .. string.format("%03d", pos+1) .. ".mp3",
                                surahList[pos+1] .. " Arabic",
                                "Arabic_" .. (pos+1) .. ".mp3"
                            )
                        elseif w == 2 then
                            local url2, fn2 = transUrl(pos + 1)
                            dlFile(url2, "Tarjuma-" .. surahList[pos+1], fn2)
                        else
                            showTafseerPlayerScreen(pos + 1)
                        end
                    end
                }
            )
            .show()
        return true
    end
end

-----------------------------------------------------------------
-- SCREEN: SURAH PLAYER
-----------------------------------------------------------------
function showPlayerScreen(startPos)
    if startPos then
        currentPos = startPos
        playSurah(startPos)
    end
    activity.setContentView(loadlayout({
        LinearLayout, orientation = "vertical",
        layout_width = "fill", layout_height = "fill",
        -- Row 1: Now playing + settings
        {
            LinearLayout, orientation = "horizontal",
            layout_width = "fill", layout_height = "0", layout_weight = "1",
            gravity = "center_vertical",
            {
                TextView, id = "nowPlayingTxt",
                text = surahList[currentPos],
                textSize = "16sp", layout_weight = "1", padding = "8dp"
            },
            { Button, id = "moreBtn", text = "鈿� More" }
        },
        -- Row 2: Seekbar + time
        {
            LinearLayout, orientation = "horizontal",
            layout_width = "fill", layout_height = "0", layout_weight = "1",
            gravity = "center",
            { TextView, id = "currentTxt", text = "00:00", layout_weight = "1", gravity = "center" },
            { SeekBar, id = "seekBar", layout_weight = "4" },
            { TextView, id = "totalTxt",   text = "00:00", layout_weight = "1", gravity = "center" }
        },
        -- Row 3: Mode buttons
        {
            LinearLayout, orientation = "horizontal",
            layout_width = "fill", layout_height = "0", layout_weight = "1",
            {
                Button, id = "tarjumaBtn", text = "馃寪 Tarjuma: OFF",
                layout_width = "0", layout_weight = "1",
                layout_height = "fill", layout_margin = "2dp"
            },
            {
                Button, id = "ayahModeBtn", text = "馃帶 Ayat: OFF",
                layout_width = "0", layout_weight = "1",
                layout_height = "fill", layout_margin = "2dp"
            },
            {
                Button, id = "dlBothBtn", text = "猬� DL Both",
                layout_width = "0", layout_weight = "1",
                layout_height = "fill", layout_margin = "2dp"
            }
        },
        -- Row 4: Controls
        {
            LinearLayout, orientation = "horizontal",
            layout_width = "fill", layout_height = "0", layout_weight = "2",
            gravity = "center",
            { Button, id = "prevBtn", text = "鈴� Prev", layout_width = "0", layout_weight = "1", layout_height = "fill" },
            { Button, id = "rwdBtn",  text = "鈼€ 10s",  layout_width = "0", layout_weight = "1", layout_height = "fill" },
            { Button, id = "playBtn", text = "Play",    layout_width = "0", layout_weight = "2", layout_height = "fill" },
            { Button, id = "fwdBtn",  text = "10s 鈻�",  layout_width = "0", layout_weight = "1", layout_height = "fill" },
            { Button, id = "nextBtn", text = "Next 鈴�", layout_width = "0", layout_weight = "1", layout_height = "fill" }
        },
        -- Row 5: Back
        {
            Button, id = "backToList", text = "猬� Back to Surah List",
            layout_width = "fill", layout_height = "0", layout_weight = "1"
        }
    }))

    moreBtn.setAllCaps(false);    tarjumaBtn.setAllCaps(false)
    ayahModeBtn.setAllCaps(false); dlBothBtn.setAllCaps(false)
    prevBtn.setAllCaps(false);    rwdBtn.setAllCaps(false)
    playBtn.setAllCaps(false);    fwdBtn.setAllCaps(false)
    nextBtn.setAllCaps(false);    backToList.setAllCaps(false)

    seekBar.setOnSeekBarChangeListener({
        onProgressChanged = function(v, p, fromUser)
            if fromUser then
                local t = ayahModeOn and (ayahPlayer or ayahTrPlayer) or player
                if t then t.seekTo(p) end
            end
        end
    })

    -- Restore button states if already playing
    if translationEnabled then
        tarjumaBtn.setText("馃寪 Tarjuma: ON (" .. transLang .. ")")
        tarjumaBtn.setBackgroundColor(0xFF388E3C)
    end
    if ayahModeOn then
        ayahModeBtn.setText("馃帶 Ayat: ON")
        ayahModeBtn.setBackgroundColor(0xFF1565C0)
    end
    if (player and player.isPlaying()) or ayahModeOn then
        playBtn.setText("Pause")
    end

    moreBtn.onClick = function()
        AlertDialog.Builder(activity)
            .setTitle("鈿� Player Options")
            .setItems({"鈴� Speed", "鈴� Seek Time", "馃寪 Tarjuma Zaban"}, {
                onClick = function(d, w)
                    if w == 0 then
                        showSpeedMenu(player or ayahPlayer)
                    elseif w == 1 then
                        showSeekMenu()
                    else
                        showTransLangMenu()
                    end
                end
            })
            .show()
    end

    tarjumaBtn.onClick = function()
        if ayahModeOn then
            Toast.makeText(activity, "Pehle Ayat Mode band karein", 0).show()
            return
        end
        translationEnabled = not translationEnabled
        if translationEnabled then
            tarjumaBtn.setText("馃寪 Tarjuma: ON (" .. transLang .. ")")
            tarjumaBtn.setBackgroundColor(0xFF388E3C)
        else
            tarjumaBtn.setText("馃寪 Tarjuma: OFF")
            tarjumaBtn.setBackgroundColor(0xFF607D8B)
            transPlayer = stopMP(transPlayer)
        end
    end

    ayahModeBtn.onClick = function()
        if not currentReciter then
            Toast.makeText(activity, "Reciter select karein", 0).show()
            return
        end
        if translationEnabled then
            Toast.makeText(activity, "Pehle Tarjuma band karein", 0).show()
            return
        end
        ayahModeOn = not ayahModeOn
        if ayahModeOn then
            ayahModeBtn.setText("馃帶 Ayat: ON")
            ayahModeBtn.setBackgroundColor(0xFF1565C0)
            if updater then handler.removeCallbacks(updater) end
            player = stopMP(player)
            curAyah = 1
            playAyahAt(currentPos, 1)
            playBtn.setText("Pause")
        else
            ayahModeBtn.setText("馃帶 Ayat: OFF")
            ayahModeBtn.setBackgroundColor(0xFF607D8B)
            if ayahUpdater then handler.removeCallbacks(ayahUpdater) end
            ayahPlayer   = stopMP(ayahPlayer)
            ayahTrPlayer = stopMP(ayahTrPlayer)
            playBtn.setText("Play")
        end
    end

    dlBothBtn.onClick = function()
        if not currentReciter then
            Toast.makeText(activity, "Reciter select karein", 0).show()
            return
        end
        dlFile(
            BASE_URL .. string.format("%03d", currentPos) .. ".mp3",
            surahList[currentPos] .. " Arabic",
            "Arabic_" .. currentPos .. ".mp3"
        )
        local url2, fn2 = transUrl(currentPos)
        dlFile(url2, "Tarjuma-" .. surahList[currentPos], fn2)
    end

    playBtn.onClick = function()
        if ayahModeOn then
            local ap = ayahPlayer or ayahTrPlayer
            if ap then
                if ap.isPlaying() then
                    ap.pause()
                    playBtn.setText("Play")
                else
                    ap.start()
                    playBtn.setText("Pause")
                end
            end
        elseif player then
            if player.isPlaying() then
                player.pause()
                transPlayer = stopMP(transPlayer)
                playBtn.setText("Play")
            else
                player.start()
                playBtn.setText("Pause")
            end
        elseif currentReciter then
            playSurah(currentPos)
        else
            Toast.makeText(activity, "Reciter select karein", 0).show()
        end
    end

    nextBtn.onClick = function()
        if not currentReciter then return end
        if ayahModeOn then
            if currentPos < 114 then playAyahAt(currentPos + 1, 1) end
        elseif currentPos < 114 then
            playSurah(currentPos + 1)
        end
    end

    prevBtn.onClick = function()
        if not currentReciter then return end
        if ayahModeOn then
            if currentPos > 1 then playAyahAt(currentPos - 1, 1) end
        elseif currentPos > 1 then
            playSurah(currentPos - 1)
        end
    end

    fwdBtn.onClick = function()
        local t = ayahModeOn and (ayahPlayer or ayahTrPlayer) or player
        if t then
            local np = t.getCurrentPosition() + seekTime
            if np < t.getDuration() then t.seekTo(np) end
        end
    end

    rwdBtn.onClick = function()
        local t = ayahModeOn and (ayahPlayer or ayahTrPlayer) or player
        if t then
            local np = t.getCurrentPosition() - seekTime
            t.seekTo(np > 0 and np or 0)
        end
    end

    backToList.onClick = function()
        if updater      then handler.removeCallbacks(updater)      end
        if ayahUpdater  then handler.removeCallbacks(ayahUpdater)  end
        player       = stopMP(player)
        transPlayer  = stopMP(transPlayer)
        ayahPlayer   = stopMP(ayahPlayer)
        ayahTrPlayer = stopMP(ayahTrPlayer)
        showSurahListScreen()
    end
end

-----------------------------------------------------------------
-- SCREEN: DUA LIST
-----------------------------------------------------------------
function showDuaListScreen()
    duaPlayer = stopMP(duaPlayer)
    if duaUpdater then handler.removeCallbacks(duaUpdater) end

    activity.setContentView(loadlayout({
        LinearLayout, orientation = "vertical",
        layout_width = "fill", layout_height = "fill",
        {
            LinearLayout, orientation = "horizontal",
            layout_width = "fill", layout_height = "wrap_content",
            padding = "6dp",
            {
                TextView, text = "馃げ Authentic Duaein (Hisnul Muslim)",
                textSize = "16sp", typeface = 1,
                layout_weight = "1", gravity = "center_vertical"
            },
            { Button, id = "duaHomeBtn", text = "猬� Home", layout_width = "wrap_content" }
        },
        { ListView, id = "duaLv", layout_width = "fill", layout_height = "fill" }
    }))
    duaHomeBtn.setAllCaps(false)
    duaHomeBtn.onClick = function() showHomeScreen() end

    local names = {}
    for i, d in ipairs(duaList) do
        table.insert(names, i .. ".  " .. d.name)
    end
    duaLv.setAdapter(
        ArrayAdapter(activity, android.R.layout.simple_list_item_1, names)
    )
    duaLv.onItemClick = function(p, v, pos, id)
        showDuaPlayerScreen(pos + 1)
    end
end

-----------------------------------------------------------------
-- SCREEN: DUA PLAYER
-----------------------------------------------------------------
function showDuaPlayerScreen(startPos)
    activity.setContentView(loadlayout({
        LinearLayout, orientation = "vertical",
        layout_width = "fill", layout_height = "fill",
        -- Dua title
        {
            TextView, id = "duaNowPlayingTxt", text = "",
            textSize = "14sp", gravity = "center", padding = "6dp",
            textColor = "#1A237E", typeface = 1,
            layout_width = "fill", layout_height = "wrap_content"
        },
        -- Arabic text
        {
            TextView, id = "duaArabicTxt", text = "",
            textSize = "22sp", gravity = "center", padding = "6dp",
            textColor = "#4A148C",
            layout_width = "fill", layout_height = "0", layout_weight = "2"
        },
        -- Urdu translation
        {
            TextView, id = "duaUrduTxt", text = "",
            textSize = "13sp", gravity = "center", padding = "6dp",
            textColor = "#333333",
            layout_width = "fill", layout_height = "0", layout_weight = "1"
        },
        -- Seekbar
        {
            LinearLayout, orientation = "horizontal",
            layout_width = "fill", layout_height = "wrap_content",
            padding = "4dp", gravity = "center_vertical",
            { TextView, id = "duaCurrentTxt", text = "00:00", layout_weight = "1", gravity = "center" },
            { SeekBar, id = "duaSeekBar", layout_weight = "4" },
            { TextView, id = "duaTotalTxt", text = "00:00", layout_weight = "1", gravity = "center" }
        },
        -- Controls
        {
            LinearLayout, orientation = "horizontal",
            layout_width = "fill", layout_height = "0", layout_weight = "2",
            { Button, id = "duaPrevBtn", text = "鈴� Prev", layout_width = "0", layout_weight = "1", layout_height = "fill" },
            { Button, id = "duaRwdBtn",  text = "鈼€ 5s",   layout_width = "0", layout_weight = "1", layout_height = "fill" },
            { Button, id = "duaPlayBtn", text = "鈻� Play",  layout_width = "0", layout_weight = "2", layout_height = "fill" },
            { Button, id = "duaFwdBtn",  text = "5s 鈻�",   layout_width = "0", layout_weight = "1", layout_height = "fill" },
            { Button, id = "duaNextBtn", text = "Next 鈴�", layout_width = "0", layout_weight = "1", layout_height = "fill" }
        },
        -- Download + Back
        {
            LinearLayout, orientation = "horizontal",
            layout_width = "fill", layout_height = "0", layout_weight = "1",
            {
                Button, id = "duaDlBtn", text = "猬� Download Dua",
                layout_width = "0", layout_weight = "1",
                layout_height = "fill", layout_margin = "3dp"
            },
            {
                Button, id = "duaBackBtn", text = "猬� Duas List",
                layout_width = "0", layout_weight = "1",
                layout_height = "fill", layout_margin = "3dp"
            }
        }
    }))

    duaPrevBtn.setAllCaps(false); duaRwdBtn.setAllCaps(false)
    duaPlayBtn.setAllCaps(false); duaFwdBtn.setAllCaps(false)
    duaNextBtn.setAllCaps(false); duaDlBtn.setAllCaps(false)
    duaBackBtn.setAllCaps(false)

    duaSeekBar.setOnSeekBarChangeListener({
        onProgressChanged = function(v, p, fu)
            if fu and duaPlayer then duaPlayer.seekTo(p) end
        end
    })

    playDuaAt(startPos or currentDuaPos)

    duaPlayBtn.onClick = function()
        if duaPlayer then
            if duaPlayer.isPlaying() then
                duaPlayer.pause()
                if duaUpdater then handler.removeCallbacks(duaUpdater) end
                duaPlayBtn.setText("鈻� Play")
            else
                duaPlayer.start()
                duaUpdater = mkUpdater(
                    function() return duaPlayer end,
                    function() return duaSeekBar end,
                    function() return duaCurrentTxt end
                )
                handler.post(duaUpdater)
                duaPlayBtn.setText("鈴� Pause")
            end
        else
            playDuaAt(currentDuaPos)
        end
    end

    duaPrevBtn.onClick = function()
        if currentDuaPos > 1 then playDuaAt(currentDuaPos - 1) end
    end

    duaNextBtn.onClick = function()
        if currentDuaPos < #duaList then playDuaAt(currentDuaPos + 1) end
    end

    duaRwdBtn.onClick = function()
        if duaPlayer then
            local np = duaPlayer.getCurrentPosition() - 5000
            duaPlayer.seekTo(np > 0 and np or 0)
        end
    end

    duaFwdBtn.onClick = function()
        if duaPlayer then
            local np = duaPlayer.getCurrentPosition() + 5000
            if np < duaPlayer.getDuration() then duaPlayer.seekTo(np) end
        end
    end

    duaDlBtn.onClick = function()
        local d = duaList[currentDuaPos]
        dlFile(d.audio, d.name, "Dua_" .. currentDuaPos .. ".mp3")
    end

    duaBackBtn.onClick = function()
        duaPlayer = stopMP(duaPlayer)
        if duaUpdater then handler.removeCallbacks(duaUpdater) end
        showDuaListScreen()
    end
end

-----------------------------------------------------------------
-- SCREEN: PARA (30 Paare)
-----------------------------------------------------------------
function showParaScreen()
    activity.setContentView(loadlayout({
        LinearLayout, orientation = "vertical",
        layout_width = "fill", layout_height = "fill",
        -- Header
        {
            LinearLayout, orientation = "horizontal",
            layout_width = "fill", layout_height = "wrap_content",
            padding = "6dp",
            {
                TextView, text = "馃摎 30 Paare 鈥� Juz Audio",
                textSize = "17sp", typeface = 1,
                layout_weight = "1", gravity = "center_vertical"
            },
            { Button, id = "paraHomeBtn", text = "猬� Home", layout_width = "wrap_content" }
        },
        -- Now playing title
        {
            TextView, id = "paraTitleTxt",
            text = "Neeche se Para select karein",
            textSize = "14sp", gravity = "center",
            padding = "6dp", textColor = "#1B5E20",
            layout_width = "fill", layout_height = "wrap_content"
        },
        -- Seekbar
        {
            LinearLayout, orientation = "horizontal",
            layout_width = "fill", layout_height = "wrap_content",
            padding = "4dp", gravity = "center_vertical",
            { TextView, id = "paraCurrentTxt", text = "00:00", layout_weight = "1", gravity = "center" },
            { SeekBar, id = "paraSeekBar", layout_weight = "4" },
            { TextView, id = "paraTotalTxt", text = "00:00", layout_weight = "1", gravity = "center" }
        },
        -- Controls
        {
            LinearLayout, orientation = "horizontal",
            layout_width = "fill", layout_height = "wrap_content",
            { Button, id = "paraPrevBtn", text = "鈴� Prev",    layout_width = "0", layout_weight = "1" },
            { Button, id = "paraPlayBtn", text = "鈻� Play",     layout_width = "0", layout_weight = "2" },
            { Button, id = "paraNextBtn", text = "Next 鈴�",    layout_width = "0", layout_weight = "1" }
        },
        -- Tarjuma + Download
        {
            LinearLayout, orientation = "horizontal",
            layout_width = "fill", layout_height = "wrap_content",
            {
                Button, id = "paraTrBtn", text = "馃寪 Tarjuma: OFF",
                layout_width = "0", layout_weight = "1", layout_margin = "2dp"
            },
            {
                Button, id = "paraDlBtn", text = "猬� DL Para+Tarjuma",
                layout_width = "0", layout_weight = "1", layout_margin = "2dp"
            }
        },
        -- Para list
        { ListView, id = "paraLv", layout_width = "fill", layout_height = "fill" }
    }))

    paraHomeBtn.setAllCaps(false); paraPrevBtn.setAllCaps(false)
    paraPlayBtn.setAllCaps(false); paraNextBtn.setAllCaps(false)
    paraTrBtn.setAllCaps(false);   paraDlBtn.setAllCaps(false)

    paraSeekBar.setOnSeekBarChangeListener({
        onProgressChanged = function(v, p, fu)
            if fu and paraPlayer then paraPlayer.seekTo(p) end
        end
    })

    local pnames = {}
    for i = 1, 30 do
        table.insert(pnames, "Para " .. i .. ": " .. paraNames[i])
    end
    paraLv.setAdapter(
        ArrayAdapter(activity, android.R.layout.simple_list_item_1, pnames)
    )
    paraLv.onItemClick = function(p, v, pos, id)
        playPara(pos + 1)
    end

    paraHomeBtn.onClick = function()
        paraPlayer      = stopMP(paraPlayer)
        paraTransPlayer = stopMP(paraTransPlayer)
        if paraUpdater then handler.removeCallbacks(paraUpdater) end
        showHomeScreen()
    end

    paraTrBtn.onClick = function()
        paraTransEnabled = not paraTransEnabled
        if paraTransEnabled then
            paraTrBtn.setText("馃寪 Tarjuma: ON (" .. transLang .. ")")
            paraTrBtn.setBackgroundColor(0xFF388E3C)
        else
            paraTrBtn.setText("馃寪 Tarjuma: OFF")
            paraTrBtn.setBackgroundColor(0xFF607D8B)
            paraTransPlayer = stopMP(paraTransPlayer)
        end
    end

    paraPlayBtn.onClick = function()
        if paraPlayer then
            if paraPlayer.isPlaying() then
                paraPlayer.pause()
                paraPlayBtn.setText("鈻� Play")
            else
                paraPlayer.start()
                paraPlayBtn.setText("鈴� Pause")
            end
        else
            playPara(currentPara)
        end
    end

    paraPrevBtn.onClick = function()
        if currentPara > 1 then playPara(currentPara - 1) end
    end

    paraNextBtn.onClick = function()
        if currentPara < 30 then playPara(currentPara + 1) end
    end

    paraDlBtn.onClick = function()
        local nn  = currentPara < 10 and ("0" .. currentPara) or tostring(currentPara)
        dlFile(
            PARA_BASE .. "Para%20" .. nn .. ".mp3",
            "Para " .. currentPara .. " 鈥� " .. paraNames[currentPara],
            "Para_" .. currentPara .. ".mp3"
        )
        local firstS    = paraFirstSurah[currentPara] or 1
        local turl, tfn = transUrl(firstS)
        dlFile(turl, "ParaTarjuma-" .. paraNames[currentPara], "ParaTrans_" .. currentPara .. ".mp3")
    end
end

-----------------------------------------------------------------
-- SCREEN: TAFSEER LIST
-----------------------------------------------------------------
function showTafseerListScreen()
    activity.setContentView(loadlayout({
        LinearLayout, orientation = "vertical",
        layout_width = "fill", layout_height = "fill",
        {
            LinearLayout, orientation = "horizontal",
            layout_width = "fill", layout_height = "wrap_content",
            padding = "6dp",
            {
                TextView, text = "馃摐 Tafseer Ibn Kaseer 鈥� Urdu Audio",
                textSize = "16sp", typeface = 1,
                layout_weight = "1", gravity = "center_vertical"
            },
            { Button, id = "tafHomeBtn", text = "猬� Home", layout_width = "wrap_content" }
        },
        { ListView, id = "tafLv", layout_width = "fill", layout_height = "fill" }
    }))
    tafHomeBtn.setAllCaps(false)
    tafHomeBtn.onClick = function() showHomeScreen() end

    tafLv.setAdapter(
        ArrayAdapter(activity, android.R.layout.simple_list_item_1, surahList)
    )
    tafLv.onItemClick = function(p, v, pos, id)
        showTafseerPlayerScreen(pos + 1)
    end
end

-----------------------------------------------------------------
-- SCREEN: TAFSEER PLAYER
-----------------------------------------------------------------
function showTafseerPlayerScreen(startPos)
    if startPos then currentTafseerPos = startPos end
    activity.setContentView(loadlayout({
        LinearLayout, orientation = "vertical",
        layout_width = "fill", layout_height = "fill",
        -- Header
        {
            LinearLayout, orientation = "horizontal",
            layout_width = "fill", layout_height = "wrap_content",
            gravity = "center_vertical",
            {
                TextView, id = "tafTitleTxt",
                text = "Tafseer: " .. surahList[currentTafseerPos],
                textSize = "16sp", typeface = 1,
                layout_weight = "1", padding = "8dp", textColor = "#1B5E20"
            },
            { Button, id = "tafDlBtn", text = "猬� Download", layout_width = "wrap_content" }
        },
        -- Seekbar
        {
            LinearLayout, orientation = "horizontal",
            layout_width = "fill", layout_height = "wrap_content",
            padding = "4dp", gravity = "center_vertical",
            { TextView, id = "tafCurrentTxt", text = "00:00", layout_weight = "1", gravity = "center" },
            { SeekBar, id = "tafSeekBar", layout_weight = "4" },
            { TextView, id = "tafTotalTxt", text = "00:00", layout_weight = "1", gravity = "center" }
        },
        -- Controls
        {
            LinearLayout, orientation = "horizontal",
            layout_width = "fill", layout_height = "wrap_content",
            { Button, id = "tafPrevBtn", text = "鈴� Prev",   layout_width = "0", layout_weight = "1" },
            { Button, id = "tafPlayBtn", text = "鈻� Play",    layout_width = "0", layout_weight = "2" },
            { Button, id = "tafNextBtn", text = "Next 鈴�",   layout_width = "0", layout_weight = "1" }
        },
        -- Back button
        {
            Button, id = "tafBackBtn", text = "猬� Back to Tafseer List",
            layout_width = "fill", layout_height = "wrap_content",
            layout_margin = "4dp"
        }
    }))

    tafDlBtn.setAllCaps(false);  tafPrevBtn.setAllCaps(false)
    tafPlayBtn.setAllCaps(false); tafNextBtn.setAllCaps(false)
    tafBackBtn.setAllCaps(false)

    tafSeekBar.setOnSeekBarChangeListener({
        onProgressChanged = function(v, p, fu)
            if fu and tafseerPlayer then tafseerPlayer.seekTo(p) end
        end
    })

    playTafseer(currentTafseerPos)

    tafPlayBtn.onClick = function()
        if tafseerPlayer then
            if tafseerPlayer.isPlaying() then
                tafseerPlayer.pause()
                tafPlayBtn.setText("鈻� Play")
            else
                tafseerPlayer.start()
                tafPlayBtn.setText("鈴� Pause")
            end
        else
            playTafseer(currentTafseerPos)
        end
    end

    tafPrevBtn.onClick = function()
        if currentTafseerPos > 1 then
            currentTafseerPos = currentTafseerPos - 1
            playTafseer(currentTafseerPos)
        end
    end

    tafNextBtn.onClick = function()
        if currentTafseerPos < 114 then
            currentTafseerPos = currentTafseerPos + 1
            playTafseer(currentTafseerPos)
        end
    end

    tafDlBtn.onClick = function()
        local nm  = tafseerNames[currentTafseerPos]
        local url = "https://archive.org/download/" .. currentTafseerPos .. "." .. nm
                    .. "/" .. currentTafseerPos .. "." .. nm .. ".mp3"
        dlFile(url, "Tafseer-" .. surahList[currentTafseerPos], "Tafseer_" .. currentTafseerPos .. ".mp3")
    end

    tafBackBtn.onClick = function()
        tafseerPlayer = stopMP(tafseerPlayer)
        if tafseerUpdater then handler.removeCallbacks(tafseerUpdater) end
        showTafseerListScreen()
    end
end

-----------------------------------------------------------------
-- SCREEN: NOORANI QAIDA
-----------------------------------------------------------------
function showNooraniScreen()
    nqPlayer = stopMP(nqPlayer)

    local sv = ScrollView(activity)
    local ll = LinearLayout(activity)
    ll.setOrientation(1)
    ll.setPadding(10, 10, 10, 10)

    -- Header
    local hdr = TextView(activity)
    hdr.setText("馃摽 Noorani Qaida 鈥� 賳賵乇丕賳蹖 賯丕毓丿蹃")
    hdr.setTextSize(20)
    hdr.setTypeface(nil, 1)
    hdr.setGravity(17)
    hdr.setTextColor(0xFF1B5E20)
    hdr.setPadding(0, 0, 0, 4)
    ll.addView(hdr)

    local sub = TextView(activity)
    sub.setText("Harf pe click karein 鈥� Qari ki awaaz mein sunein | 猬� Download bhi available")
    sub.setTextSize(12)
    sub.setGravity(17)
    sub.setTextColor(0xFF555555)
    sub.setPadding(0, 0, 0, 10)
    ll.addView(sub)

    -- Column headers
    local hrow = LinearLayout(activity)
    hrow.setOrientation(0)
    hrow.setPadding(6, 4, 6, 4)
    hrow.setBackgroundColor(0xFF1B5E20)
    local hnames = {"#", "Harf", "Urdu Naam", "English", "猬�"}
    local hwts   = {0.4, 1.0, 1.0, 1.0, 0.5}
    for i = 1, #hnames do
        local htv = TextView(activity)
        htv.setText(hnames[i])
        htv.setTextSize(13)
        htv.setTextColor(0xFFFFFFFF)
        htv.setTypeface(nil, 1)
        htv.setGravity(17)
        htv.setLayoutParams(
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, hwts[i])
        )
        hrow.addView(htv)
    end
    ll.addView(hrow)

    -- Each letter row
    for i = 1, #noorani do
        local q   = noorani[i]
        local row = LinearLayout(activity)
        row.setOrientation(0)
        row.setPadding(6, 8, 6, 8)
        row.setBackgroundColor(i % 2 == 0 and 0xFFE8F5E9 or 0xFFF9FBE7)
        local rlp = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        )
        rlp.bottomMargin = 2
        row.setLayoutParams(rlp)

        -- Number
        local numTv = TextView(activity)
        numTv.setText(tostring(i))
        numTv.setTextSize(12)
        numTv.setTextColor(0xFF888888)
        numTv.setGravity(17)
        numTv.setLayoutParams(
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 0.4)
        )

        -- Arabic letter button
        local lBtn = Button(activity)
        lBtn.setText(q[1])
        lBtn.setTextSize(32)
        lBtn.setTextColor(0xFF1A237E)
        lBtn.setAllCaps(false)
        lBtn.setBackgroundColor(0xFFE3F2FD)
        lBtn.setContentDescription(q[3])
        lBtn.setLayoutParams(
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1.0)
        )

        -- Urdu name
        local uTv = TextView(activity)
        uTv.setText(q[2])
        uTv.setTextSize(15)
        uTv.setTextColor(0xFF4A148C)
        uTv.setGravity(17)
        uTv.setLayoutParams(
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1.0)
        )

        -- English name
        local eTv = TextView(activity)
        eTv.setText(q[3])
        eTv.setTextSize(13)
        eTv.setTextColor(0xFF555555)
        eTv.setGravity(17)
        eTv.setLayoutParams(
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1.0)
        )

        -- Download button
        local dBtn = Button(activity)
        dBtn.setText("猬�")
        dBtn.setAllCaps(false)
        dBtn.setTextSize(12)
        dBtn.setBackgroundColor(0xFF1565C0)
        dBtn.setTextColor(0xFFFFFFFF)
        dBtn.setContentDescription("Download " .. q[3])
        dBtn.setLayoutParams(
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        )

        -- Audio: Qari Maher voice (first ayah of mapped short surah)
        local sn       = nqSurahMap[i]
        local audioUrl = ARABIC_AYAH .. string.format("%03d", sn) .. "001.mp3"
        local audioFn  = "QaidaLetter_" .. i .. ".mp3"

        lBtn.onClick = function()
            nqPlayer = stopMP(nqPlayer)
            local fu = smartUrl(audioUrl, audioFn)
            if fu then
                Toast.makeText(activity, q[2] .. " 鈥� " .. q[3], 0).show()
                nqPlayer = newMP(
                    fu,
                    function(mp) mp.start() end,
                    function(mp) nqPlayer = stopMP(nqPlayer) end,
                    function() nqPlayer = stopMP(nqPlayer) end
                )
            else
                Toast.makeText(activity, "Internet nahi. Pehle download karein.", 0).show()
            end
        end

        dBtn.onClick = function()
            dlFile(audioUrl, q[2] .. " (" .. q[3] .. ")", audioFn)
        end

        row.addView(numTv)
        row.addView(lBtn)
        row.addView(uTv)
        row.addView(eTv)
        row.addView(dBtn)
        ll.addView(row)
    end

    -- Back button
    local backBtn2 = Button(activity)
    backBtn2.setText("猬� Back to Home")
    backBtn2.setAllCaps(false)
    backBtn2.setBackgroundColor(0xFF607D8B)
    backBtn2.setTextColor(0xFFFFFFFF)
    local bblp = LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.MATCH_PARENT,
        LinearLayout.LayoutParams.WRAP_CONTENT
    )
    bblp.topMargin = 10
    backBtn2.setLayoutParams(bblp)
    backBtn2.onClick = function()
        nqPlayer = stopMP(nqPlayer)
        showHomeScreen()
    end
    ll.addView(backBtn2)

    sv.addView(ll)
    activity.setContentView(sv)
end

-----------------------------------------------------------------
-- START
-----------------------------------------------------------------
activity.setTitle(APP_NAME)
showHomeScreen()

function onDestroy()
    stopAll()
end