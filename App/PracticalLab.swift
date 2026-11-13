import SwiftUI

let extraActivities: [Activity] = [
    Activity(subject:.physics,title:"Rampa dhe lartësia",materials:"Makinë lodër, karton i fortë, dy libra, vizore.",
             steps:["Ndërto një rampë të ulët mbi një tavolinë të lirë ose dysheme.","Lësho lodrën nga qetësia dhe mat sa larg shkon pas rampës.","Rrit pak lartësinë dhe përsërit tri herë për secilën lartësi."],
             discuss:"Si lidhet lartësia fillestare me energjinë? Ku shkon energjia kur lodra ndalet?"),
    Activity(subject:.physics,title:"Ura prej letre",materials:"Dy libra, një fletë, monedha.",
             steps:["Vendos librat si mbështetëse dhe një fletë të sheshtë mes tyre.","Shto monedha nga një derisa fleta të përkulet.","Palose fletën si fizarmonikë dhe përsërit me të njëjtën largësi mes librave."],
             discuss:"Pse forma e mbajtëses ndryshon sa peshë mund të mbajë?"),
    Activity(subject:.physics,title:"Ora me lavjerrës",materials:"Pe i shkurtër, gomë lapsi, kronometër, vizore.",
             steps:["Lidh gomën në pe dhe mbaje mbi një sipërfaqe të lirë.","Lëkunde pak dhe mat kohën e 10 lëkundjeve.","Përsërit me gjatësi tjetër. Pjesëto kohën me 10 për të gjetur periodën."],
             discuss:"A përputhet prirja me T = 2π√(L/g)? Si ndikon matja e shumë lëkundjeve te gabimi?"),
    Activity(subject:.physics,title:"Barka prej flete alumini",materials:"Enë e cekët me ujë, fletë alumini, monedha.",
             steps:["Formo një barkë të hapur me fund të gjerë.","Shto monedha me radhë dhe numëroji.","Provo një formë tjetër me të njëjtën sasi alumini."],
             discuss:"Si ndikon vëllimi i ujit të zhvendosur te forca ngritëse?"),
    Activity(subject:.physics,title:"Hija që ndryshon",materials:"Elektrik dore, objekt i vogël, letër, vizore.",
             steps:["Drejto dritën nga objekti te letra.","Mbaj objektin e letrën në vend dhe ndrysho largësinë e elektrikës.","Mat madhësinë e hijes në tri pozicione."],
             discuss:"Si shpjegohet zmadhimi i hijes me përhapjen drejtvizore të dritës?"),
    Activity(subject:.math,title:"Gjuetia e numrit π",materials:"Tri objekte rrethore, pe, vizore.",
             steps:["Mat perimetrin e secilit rreth me pe.","Mat diametrin nëpër qendër.","Pjesëto perimetrin me diametrin dhe krahaso tri rezultatet."],
             discuss:"Pse raportet afrohen me të njëjtin numër? Çfarë i shkakton ndryshimet?"),
    Activity(subject:.math,title:"Dy zare, shumë rezultate",materials:"Dy zare, letër, laps.",
             steps:["Parashiko shumën më të shpeshtë.","Hidhi zaret 60 herë dhe numëro shumat nga 2 deri në 12.","Ndërto diagram shtyllor dhe krahasoje me laboratorin virtual."],
             discuss:"A doli 7 më shpesh në provën tuaj? A është e detyrueshme kjo për çdo seri?"),
    Activity(subject:.math,title:"Trekëndësha në një fletë",materials:"Letër, laps, vizore, gërshërë me ndihmën e një të rrituri.",
             steps:["Vizato dhe prit një trekëndësh.","Shkëput tri këndet dhe vendosi me kulmet bashkë.","Përsërit me një trekëndësh me formë tjetër."],
             discuss:"Çfarë këndi formojnë së bashku tri këndet e trekëndëshit?"),
    Activity(subject:.math,title:"I njëjti perimetër",materials:"Pe 40 cm, vizore, letër.",
             steps:["Formo me pe drejtkëndësh 4 cm × 16 cm.","Formo pastaj 8 cm × 12 cm dhe 10 cm × 10 cm.","Llogarit syprinën për secilin."],
             discuss:"Cili drejtkëndësh ka syprinën më të madhe për këtë perimetër?"),
    Activity(subject:.math,title:"Simetria me palosje",materials:"Fletë, laps, disa pika ngjyre.",
             steps:["Palose fletën në mes dhe shëno boshtin.","Vizato disa pika në njërën anë dhe ndërto pikat pasqyrë.","Mat largësinë e çifteve të pikave nga boshti."],
             discuss:"Çfarë ruan pasqyrimi? A mund të ndërtosh figurë me dy boshte simetrie?"),
    Activity(subject:.chemistry,title:"Uji dhe vaji në pushim",materials:"Gotë transparente, pak ujë, vaj ushqimor, lugë.",
             steps:["Hidh ujë dhe një shtresë të hollë vaji në gotë.","Përzieji lehtë dhe vëzhgo menjëherë.","Lëri në pushim dhe shëno çfarë ndodh pas pak minutash."],
             discuss:"Si dallohet një shpërndarje e përkohshme nga një tretësirë?"),
    Activity(subject:.chemistry,title:"Kristale me avullim",materials:"Pak kripë, ujë, enë e cekët, lugë.",
             steps:["Tret pak kripë në ujë në temperaturë dhome.","Vendos një shtresë të hollë të tretësirës në enë.","Lëre disa ditë në vend të sigurt dhe shëno ndryshimet çdo ditë."],
             discuss:"Çfarë largohet gjatë avullimit dhe çfarë mbetet në enë?"),
    Activity(subject:.chemistry,title:"Ngjyrat brenda bojës",materials:"Letër filtri kafeje, laps, marker që lahet me ujë, gotë me pak ujë.",
             steps:["Vendos një pikë me marker mbi një vijë lapsi afër fundit të letrës.","Zhyte vetëm skajin poshtë pikës së bojës.","Shiko si ngjitet uji dhe nëse ngjyrat ndahen."],
             discuss:"Pse përbërësit e bojës mund të lëvizin me shpejtësi të ndryshme?"),
    Activity(subject:.chemistry,title:"A ndihmon përzierja?",materials:"Dy gota me sasi të barabarta uji, dy sasi të barabarta sheqeri, lugë, kronometër.",
             steps:["Shto sheqerin në të dy gotat njëkohësisht.","Përziej vetëm njërën gotë me ritëm të rregullt.","Mat kohën deri kur grimcat nuk duken më."],
             discuss:"A ndryshoi shpejtësia e tretjes? Cilat kushte mbajte të njëjta?"),
    Activity(subject:.chemistry,title:"Ndarja me filtrim",materials:"Pak rërë, ujë, letër filtri, dy gota, hinkë.",
             steps:["Përziej pak rërë me ujë.","Kalo përzierjen nëpër letër filtri në gotën tjetër.","Krahaso çfarë mbetet në filtër me atë që kalon. Uji përdoret vetëm për vëzhgim."],
             discuss:"A do ta ndante i njëjti filtër kripën e tretur nga uji? Pse?"),
    Activity(subject:.biology,title:"Farat dhe uji",materials:"Fara fasuleje, dy enë të vogla, letër kuzhine, ujë.",
             steps:["Vendos nga disa fara mbi letër në secilën enë.","Mbaj njërën letër të lagësht dhe tjetrën të thatë, në të njëjtin vend.","Shëno çdo ditë për një javë sa fara mbijnë. Hidhi mostrat nëse shfaqet myk."],
             discuss:"A mjafton një farë për të nxjerrë përfundim? Çfarë do të përsërisje?"),
    Activity(subject:.biology,title:"Gjethet dhe uji në ajër",materials:"Bimë në vazo, qese transparente e pastër, lidhëse e butë.",
             steps:["Mbulo disa gjethe me qese të pastër dhe lidhe lirshëm rreth degës.","Mbaje bimën në dritë të tërthortë dhe vëzhgo për disa orë.","Krahaso me një qese bosh pranë saj, pastaj hiqi qeset."],
             discuss:"Nga mund të vijnë pikëzat? Si ndihmon qesja bosh si krahasim?"),
    Activity(subject:.biology,title:"Patatja dhe osmoza",materials:"Dy copa të ngjashme patateje të prera nga një i rritur, dy gota, ujë, kripë, peshore.",
             steps:["Mat masën e secilës copë.","Vendos njërën në ujë dhe tjetrën në ujë të kripur për të njëjtën kohë.","Pas rreth një ore thaji lehtë nga jashtë dhe peshoji përsëri."],
             discuss:"Në cilën anë të membranave ishte më i ulët potenciali i ujit? Si ndryshoi masa?"),
    Activity(subject:.biology,title:"Venat e gjethes",materials:"Gjethe e rënë, fletë, laps i butë.",
             steps:["Vendos gjethen poshtë fletës.","Kalo lapsin lehtë mbi fletë që të dalë modeli i nervaturës.","Krahaso dy gjethe të llojeve të ndryshme."],
             discuss:"Si ndihmon rrjeti i nervaturës në transportin e ujit dhe lëndëve organike?"),
    Activity(subject:.biology,title:"Zinxhiri ushqimor me karta",materials:"Letër, laps, figura bimësh dhe kafshësh.",
             steps:["Krijo karta për bar, lepur, dhelpër dhe dekompozues.","Lidhi kartat me shigjeta sipas kalimit të energjisë.","Shto një prodhues dhe konsumator tjetër për të formuar rrjetë."],
             discuss:"Çfarë mund të ndodhë me pjesën tjetër të rrjetës nëse pakësohet një popullatë?")
]

struct PracticalActivityView: View {
    let activity: Activity
    @AppStorage private var note: String
    @AppStorage private var completed: String
    init(activity: Activity) {
        self.activity = activity
        _note = AppStorage(wrappedValue:"","activityNote."+activity.id)
        _completed = AppStorage(wrappedValue:"","activitySteps."+activity.id)
    }
    var body: some View {
        Page {
            Text(activity.title).font(.largeTitle.bold())
            SectionText(heading:"Materialet",text:activity.materials)
            ForEach(activity.steps.indices,id: \.self) { index in
                Toggle(isOn: Binding(get: {
                    completed.split(separator:"|").contains(Substring(String(index)))
                }, set: { checked in
                    var ids = Set(completed.split(separator:"|").map(String.init))
                    if checked { ids.insert(String(index)) } else { ids.remove(String(index)) }
                    completed = ids.sorted().joined(separator:"|")
                })) {
                    Text("\(index+1). " + activity.steps[index])
                }.toggleStyle(.switch)
            }
            SectionText(heading:"Diskutoni së bashku",text:activity.discuss)
            Text("Parashikimi, matjet dhe përfundimi im").font(.headline)
            TextEditor(text:$note).frame(minHeight:140).padding(6)
                .glass(cornerRadius: 12)
                .accessibilityLabel("Fletorja e vëzhgimeve")
            Text("Shënimet ruhen në këtë llogari.").font(.footnote)
            ShareLink(item: activity.title+"\n\n"+note) {
                Label("Ndaj vëzhgimin",systemImage:"square.and.arrow.up")
            }
        }
    }
}
