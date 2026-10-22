// WasteTrack Prototype (Flutter) - ข้อมูลจำลองทั้งหมด ไม่ต้องใช้ API Key / Supabase
// ครอบคลุม: คำร้อง, ติดตามรถ+Geofence+Haversine, Clarke-Wright, ค่าธรรมเนียม+ป๊อปอัป, Dashboard, RBAC (เลือกบทบาท)
import 'dart:math' as math;
import 'package:flutter/material.dart';

void main() => runApp(const WasteTrackApp());

// ===================== Utils / Algorithms =====================
class LL {
  final double lat, lng;
  const LL(this.lat, this.lng);
}

/// Haversine Formula (เมตร)
double haversine(LL a, LL b) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLa = rad(b.lat - a.lat), dLo = rad(b.lng - a.lng);
  final h = math.pow(math.sin(dLa / 2), 2) +
      math.cos(rad(a.lat)) * math.cos(rad(b.lat)) * math.pow(math.sin(dLo / 2), 2);
  return 2 * r * math.asin(math.sqrt(h));
}

/// Clarke-Wright Savings (รถ 1 คัน ไม่จำกัดความจุ) คืนลำดับ index ของ pts
List<int> clarkeWright(List<LL> pts, LL depot) {
  final n = pts.length;
  double d0(int i) => haversine(depot, pts[i]);
  double d(int i, int j) => haversine(pts[i], pts[j]);
  var routes = List<List<int>>.generate(n, (i) => [i]);
  final sav = <List<num>>[];
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      sav.add([i, j, d0(i) + d0(j) - d(i, j)]);
    }
  }
  sav.sort((a, b) => b[2].compareTo(a[2]));
  for (final s in sav) {
    final i = s[0].toInt(), j = s[1].toInt();
    final ri = routes.indexWhere((r) => r.contains(i));
    final rj = routes.indexWhere((r) => r.contains(j));
    if (ri == rj) continue;
    final a = routes[ri], b = routes[rj];
    List<int>? m;
    if (a.last == i && b.first == j) {
      m = [...a, ...b];
    } else if (a.first == i && b.last == j) {
      m = [...b, ...a];
    } else if (a.last == i && b.last == j) {
      m = [...a, ...b.reversed];
    } else if (a.first == i && b.first == j) {
      m = [...a.reversed, ...b];
    }
    if (m == null) continue;
    routes
      ..removeAt(math.max(ri, rj))
      ..removeAt(math.min(ri, rj))
      ..add(m);
  }
  return routes.expand((r) => r).toList();
}

double routeLen(List<LL> r, LL start) {
  var t = 0.0;
  var prev = start;
  for (final p in r) {
    t += haversine(prev, p);
    prev = p;
  }
  return t;
}

String fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year + 543}';

// ===================== Models / State =====================
const villages = ['หมู่ 1', 'หมู่ 2', 'หมู่ 3'];
const complaintStatuses = ['รับเรื่อง', 'กำลังดำเนินการ', 'เสร็จสิ้น'];
const feeStatuses = [
  'รอแจ้งกำหนดการ', 'นัดหมายแล้ว', 'รอดำเนินการ', 'จัดเก็บแล้ว',
  'ไม่พบผู้อยู่อาศัย', 'นัดหมายใหม่', 'ค้างดำเนินการ'
];
const geofenceRadius = 50.0; // เมตร

class Complaint {
  final String id, detail, village, channel;
  String status = 'รับเรื่อง';
  final List<String> history = [];
  Complaint(this.id, this.detail, this.village, this.channel);
}

class CPoint {
  final String label, name;
  final LL pos;
  String status = 'pending'; // pending | done | failed
  String? reason;
  CPoint(this.label, this.name, this.pos);
}

class Household {
  final String no, owner, village, phone;
  String status = 'รอแจ้งกำหนดการ';
  final List<String> history = [];
  Household(this.no, this.owner, this.village, this.phone);
}

class Notice {
  final String village, text;
  bool acked = false;
  Notice(this.village, this.text);
}

class AppState extends ChangeNotifier {
  final depot = const LL(19.9100, 99.1450);
  late LL truck = depot;

  final complaints = <Complaint>[
    Complaint('sws0001', 'ขยะล้นถังหน้าตลาด', 'หมู่ 1', 'app')
      ..status = 'กำลังดำเนินการ'
      ..history.add('เริ่มต้น • ประชาชน • สร้างคำร้อง'),
  ];
  final points = <CPoint>[
    CPoint('A', 'ตลาด', const LL(19.9120, 99.1475)),
    CPoint('B', 'วัด', const LL(19.9145, 99.1440)),
    CPoint('C', 'โรงเรียน', const LL(19.9090, 99.1500)),
    CPoint('D', 'สี่แยกบ้านใหม่', const LL(19.9165, 99.1505)),
    CPoint('E', 'ศาลาประชาคม', const LL(19.9070, 99.1425)),
    CPoint('F', 'ท้ายหมู่บ้าน', const LL(19.9130, 99.1530)),
  ];
  final households = <Household>[
    Household('12/1', 'สมชาย ใจดี', 'หมู่ 1', '0812345678'),
    Household('15', 'สมหญิง สุขใจ', 'หมู่ 1', '0898765432'),
    Household('7', 'ลุงแก้ว', 'หมู่ 2', '0811111111'),
    Household('20', 'ป้าดา', 'หมู่ 3', '0822222222'),
  ];
  final notices = <Notice>[];

  String stamp(String who, String msg) {
    final t = DateTime.now();
    final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return '${fmtDate(t)} $hm • $who • $msg';
  }

  Complaint addComplaint(String detail, String village, String channel) {
    final c = Complaint('sws${(complaints.length + 1).toString().padLeft(4, '0')}', detail, village, channel);
    c.history.add(stamp(channel == 'counter' ? 'เจ้าหน้าที่หน้าเคาน์เตอร์' : 'ประชาชน', 'สร้างคำร้อง'));
    complaints.add(c);
    notifyListeners();
    return c;
  }

  void setComplaint(Complaint c, String s) {
    c.status = s;
    c.history.add(stamp('หัวหน้าฝ่าย', 'เปลี่ยนสถานะเป็น $s'));
    notifyListeners();
  }

  void setFee(Household h, String s) {
    h.status = s;
    h.history.add(stamp('เจ้าหน้าที่บัญชี', s));
    notifyListeners();
  }

  /// สร้างรอบ/ประกาศกำหนดการ -> เปลี่ยนสถานะครัวเรือน + สร้างแจ้งเตือน (ป๊อปอัป/Push จำลอง)
  void announce(String village, DateTime date, {bool resched = false}) {
    for (final h in households.where((h) => h.village == village)) {
      if (resched && h.status == 'ไม่พบผู้อยู่อาศัย') setFee(h, 'นัดหมายใหม่');
      if (!resched && h.status == 'รอแจ้งกำหนดการ') setFee(h, 'นัดหมายแล้ว');
    }
    notices.add(Notice(village,
        '${resched ? "เปลี่ยนวันนัดหมาย: " : ""}เจ้าหน้าที่จะเข้าจัดเก็บค่าธรรมเนียม $village วันที่ ${fmtDate(date)}'));
    notifyListeners();
  }

  List<CPoint> pendingRoute() {
    final p = points.where((e) => e.status == 'pending').toList();
    if (p.isEmpty) return [];
    final order = clarkeWright(p.map((e) => e.pos).toList(), truck);
    final r = order.map((i) => p[i]).toList();
    if (haversine(truck, r.first.pos) > haversine(truck, r.last.pos)) return r.reversed.toList();
    return r;
  }

  void resetRound() {
    for (final p in points) {
      p.status = 'pending';
      p.reason = null;
    }
    truck = depot;
    notifyListeners();
  }

  void changed() => notifyListeners();
}

final app = AppState();

// ===================== App / Role selection =====================
class WasteTrackApp extends StatelessWidget {
  const WasteTrackApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'WasteTrack',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
        home: const RoleScreen(),
      );
}

class RoleScreen extends StatelessWidget {
  const RoleScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final roles = <(String, IconData, Widget)>[
      ('ประชาชน (ไม่ต้องล็อกอิน)', Icons.person, const CitizenHome()),
      ('พนักงานเก็บขยะ', Icons.local_shipping, const CollectorHome()),
      ('เจ้าหน้าที่หน้าเคาน์เตอร์', Icons.support_agent, const CounterHome()),
      ('เจ้าหน้าที่บัญชี/จัดเก็บค่าธรรมเนียม', Icons.receipt_long, const FeeOfficerHome()),
      ('หัวหน้าฝ่าย', Icons.dashboard, const SupervisorHome()),
      ('ผู้ดูแลระบบ', Icons.admin_panel_settings, const AdminHome()),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('WasteTrack • อบต.แม่คะ')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('ต้นแบบ (Prototype) ข้อมูลจำลอง — เลือกบทบาทเพื่อทดลองใช้งาน\n'
            'ลองกรอกครัวเรือน 12/1 เบอร์ 0812345678 ในแท็บค่าธรรมเนียมของประชาชน'),
        const SizedBox(height: 12),
        for (final r in roles)
          Card(
            child: ListTile(
              leading: Icon(r.$2),
              title: Text(r.$1),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => r.$3)),
            ),
          ),
      ]),
    );
  }
}

// ===================== Shared widgets =====================
class ComplaintForm extends StatefulWidget {
  final String channel; // app | counter
  const ComplaintForm({super.key, required this.channel});
  @override
  State<ComplaintForm> createState() => _ComplaintFormState();
}

class _ComplaintFormState extends State<ComplaintForm> {
  final detail = TextEditingController();
  final phone = TextEditingController();
  String village = villages.first;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.channel == 'counter' ? 'บันทึกคำร้องแทนประชาชน' : 'แจ้งปัญหาขยะ',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(controller: detail, maxLines: 3, decoration: const InputDecoration(labelText: 'รายละเอียด', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'เบอร์โทรศัพท์', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: village,
            decoration: const InputDecoration(labelText: 'หมู่บ้าน', border: OutlineInputBorder()),
            items: [for (final v in villages) DropdownMenuItem(value: v, child: Text(v))],
            onChanged: (v) => setState(() => village = v!),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.photo_camera),
            label: const Text('แนบรูป / ปักพิกัด (จำลอง)'),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Prototype: ใช้ image_picker + Google Maps ในเวอร์ชันจริง'))),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () {
              if (detail.text.trim().isEmpty) return;
              final c = app.addComplaint(detail.text.trim(), village, widget.channel);
              detail.clear();
              phone.clear();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('บันทึกแล้ว รหัสอ้างอิง ${c.id}')));
            },
            child: const Text('ส่งคำร้อง'),
          ),
        ]),
      ),
    );
  }
}

class ComplaintTile extends StatelessWidget {
  final Complaint c;
  final bool editable;
  const ComplaintTile(this.c, {super.key, this.editable = false});
  @override
  Widget build(BuildContext context) => Card(
        child: ExpansionTile(
          title: Text('${c.id} • ${c.detail}'),
          subtitle: Text('${c.village} • ${c.status} • ช่องทาง: ${c.channel == "app" ? "แอป" : "เคาน์เตอร์"}'),
          childrenPadding: const EdgeInsets.all(12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (editable)
              Wrap(spacing: 8, children: [
                for (final s in complaintStatuses)
                  ChoiceChip(label: Text(s), selected: c.status == s, onSelected: (_) => app.setComplaint(c, s)),
              ]),
            const SizedBox(height: 6),
            const Text('ประวัติ', style: TextStyle(fontWeight: FontWeight.bold)),
            for (final h in c.history) Text(h, style: const TextStyle(fontSize: 12)),
          ],
        ),
      );
}

class BarRow extends StatelessWidget {
  final String label;
  final int value, max;
  const BarRow(this.label, this.value, this.max, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(fontSize: 12))),
          Expanded(child: LinearProgressIndicator(value: max == 0 ? 0 : value / max, minHeight: 14)),
          SizedBox(width: 28, child: Text('$value', textAlign: TextAlign.right)),
        ]),
      );
}

Widget sectionTitle(String t) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    );

// ----- Map (วาดเอง ไม่ต้องใช้ API Key) -----
class MapView extends StatelessWidget {
  final List<CPoint> order;
  const MapView({super.key, this.order = const []});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (_, __) => AspectRatio(
          aspectRatio: 1.2,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CustomPaint(painter: _MapPainter(order), size: Size.infinite),
          ),
        ),
      );
}

class _MapPainter extends CustomPainter {
  final List<CPoint> order;
  _MapPainter(this.order);

  void _text(Canvas c, String t, Offset center, {double size = 11, Color color = Colors.white}) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(fontSize: size, color: color, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  void paint(Canvas c, Size size) {
    c.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFE8F5E9));
    final ls = [app.depot, ...app.points.map((p) => p.pos)];
    var minLa = ls.first.lat, maxLa = minLa, minLo = ls.first.lng, maxLo = minLo;
    for (final p in ls) {
      minLa = math.min(minLa, p.lat);
      maxLa = math.max(maxLa, p.lat);
      minLo = math.min(minLo, p.lng);
      maxLo = math.max(maxLo, p.lng);
    }
    const pad = 36.0;
    final midLa = (minLa + maxLa) / 2, midLo = (minLo + maxLo) / 2;
    final mLat = 111320.0, mLng = 111320.0 * math.cos(midLa * math.pi / 180);
    final sx = (size.width - 2 * pad) / math.max((maxLo - minLo) * mLng, 1);
    final sy = (size.height - 2 * pad) / math.max((maxLa - minLa) * mLat, 1);
    final sc = math.min(sx, sy); // พิกเซลต่อเมตร (สเกลเท่ากันทั้งสองแกน)
    Offset o(LL p) => Offset(size.width / 2 + (p.lng - midLo) * mLng * sc, size.height / 2 - (p.lat - midLa) * mLat * sc);

    final line = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    var prev = o(app.truck);
    for (final p in order) {
      c.drawLine(prev, o(p.pos), line);
      prev = o(p.pos);
    }
    c.drawRect(Rect.fromCenter(center: o(app.depot), width: 14, height: 14), Paint()..color = Colors.brown);
    for (final p in app.points) {
      final col = p.status == 'done' ? Colors.green : p.status == 'failed' ? Colors.red : Colors.grey;
      final pos = o(p.pos);
      c.drawCircle(
          pos,
          geofenceRadius * sc,
          Paint()
            ..color = col.withOpacity(0.5)
            ..style = PaintingStyle.stroke);
      c.drawCircle(pos, 10, Paint()..color = col);
      _text(c, p.label, pos);
    }
    final t = o(app.truck);
    c.drawCircle(t, 13, Paint()..color = Colors.white);
    c.drawCircle(t, 11, Paint()..color = Colors.blue);
    _text(c, 'รถ', t, size: 10);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

Widget mapLegend() => const Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Wrap(spacing: 12, children: [
        Text('⚪ รอจัดเก็บ'), Text('🟢 จัดเก็บแล้ว'), Text('🔴 จัดเก็บไม่ได้'), Text('🟫 อบต.'), Text('🔵 รถ'),
      ]),
    );

Widget pointList() => Column(children: [
      for (final p in app.points)
        ListTile(
          dense: true,
          leading: CircleAvatar(
              radius: 12,
              backgroundColor: p.status == 'done' ? Colors.green : p.status == 'failed' ? Colors.red : Colors.grey,
              child: Text(p.label, style: const TextStyle(color: Colors.white, fontSize: 12))),
          title: Text(p.name),
          subtitle: Text(p.status == 'done' ? 'จัดเก็บแล้ว' : p.status == 'failed' ? 'จัดเก็บไม่ได้: ${p.reason}' : 'รอจัดเก็บ'),
        ),
    ]);

// ===================== Citizen =====================
class CitizenHome extends StatefulWidget {
  const CitizenHome({super.key});
  @override
  State<CitizenHome> createState() => _CitizenHomeState();
}

class _CitizenHomeState extends State<CitizenHome> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [const _CitizenComplaints(), const _CitizenMap(), const _FeeTab()];
    return Scaffold(
      appBar: AppBar(title: const Text('ประชาชน')),
      body: pages[tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.report), label: 'คำร้อง'),
          NavigationDestination(icon: Icon(Icons.map), label: 'รถเก็บขยะ'),
          NavigationDestination(icon: Icon(Icons.receipt), label: 'ค่าธรรมเนียม'),
        ],
      ),
    );
  }
}

class _CitizenComplaints extends StatelessWidget {
  const _CitizenComplaints();
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(12), children: [
        const ComplaintForm(channel: 'app'),
        sectionTitle('ติดตามสถานะคำร้อง'),
        ListenableBuilder(
          listenable: app,
          builder: (_, __) => Column(children: [for (final c in app.complaints.reversed) ComplaintTile(c)]),
        ),
      ]);
}

class _CitizenMap extends StatelessWidget {
  const _CitizenMap();
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(12), children: [
        const MapView(),
        mapLegend(),
        ListenableBuilder(listenable: app, builder: (_, __) => pointList()),
      ]);
}

class _FeeTab extends StatefulWidget {
  const _FeeTab();
  @override
  State<_FeeTab> createState() => _FeeTabState();
}

class _FeeTabState extends State<_FeeTab> {
  final no = TextEditingController();
  final phone = TextEditingController();
  Household? h;

  Future<void> _verify() async {
    final i = app.households.indexWhere((e) => e.no == no.text.trim() && e.phone == phone.text.trim());
    if (i < 0) {
      setState(() => h = null);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ไม่พบครัวเรือน/เบอร์ไม่ตรง')));
      return;
    }
    final hh = app.households[i];
    setState(() => h = hh);
    // FR-15: ป๊อปอัปเฉพาะครัวเรือน/พื้นที่ที่เกี่ยวข้อง และไม่แสดงซ้ำหลังรับทราบ
    for (final n in app.notices.where((n) => n.village == hh.village && !n.acked).toList()) {
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.notifications_active),
          title: const Text('แจ้งกำหนดการจัดเก็บค่าธรรมเนียม'),
          content: Text(n.text),
          actions: [
            TextButton(
                onPressed: () {
                  n.acked = true;
                  Navigator.pop(ctx);
                },
                child: const Text('รับทราบ')),
          ],
        ),
      );
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final hh = h;
    return ListView(padding: const EdgeInsets.all(12), children: [
      TextField(controller: no, decoration: const InputDecoration(labelText: 'เลขที่ครัวเรือน/บ้านเลขที่', border: OutlineInputBorder())),
      const SizedBox(height: 8),
      TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'เบอร์โทรที่ลงทะเบียนไว้', border: OutlineInputBorder())),
      const SizedBox(height: 8),
      FilledButton(onPressed: _verify, child: const Text('ตรวจสอบ')),
      if (hh != null) ...[
        sectionTitle('ครัวเรือน ${hh.no} (${hh.owner}) • ${hh.village}'),
        Card(child: ListTile(title: const Text('สถานะค่าธรรมเนียม'), subtitle: Text(hh.status))),
        sectionTitle('การแจ้งเตือนย้อนหลัง'),
        for (final n in app.notices.where((n) => n.village == hh.village))
          ListTile(
            dense: true,
            leading: Icon(n.acked ? Icons.check_circle : Icons.circle_notifications, color: n.acked ? Colors.green : Colors.orange),
            title: Text(n.text),
          ),
        sectionTitle('ประวัติ'),
        for (final x in hh.history) Text(x, style: const TextStyle(fontSize: 12)),
        if (hh.history.isEmpty) const Text('ยังไม่มีประวัติ'),
      ],
    ]);
  }
}

// ===================== Waste collector =====================
class CollectorHome extends StatefulWidget {
  const CollectorHome({super.key});
  @override
  State<CollectorHome> createState() => _CollectorHomeState();
}

class _CollectorHomeState extends State<CollectorHome> {
  final prompted = <CPoint>{};

  Future<void> _step() async {
    final route = app.pendingRoute();
    if (route.isEmpty) return;
    final t = route.first;
    final d = haversine(app.truck, t.pos);
    final f = d > 120 ? 0.6 : 0.95;
    app.truck = LL(app.truck.lat + (t.pos.lat - app.truck.lat) * f, app.truck.lng + (t.pos.lng - app.truck.lng) * f);
    app.changed();
    // Geofencing: อยู่ในรัศมี -> ให้พนักงานยืนยัน (ไม่เปลี่ยนสถานะเอง, ไม่เตือนซ้ำ)
    if (haversine(app.truck, t.pos) <= geofenceRadius && !prompted.contains(t)) {
      prompted.add(t);
      await _confirm(t);
    }
  }

  Future<void> _confirm(CPoint t) async {
    final r = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('เข้าสู่จุด ${t.label}: ${t.name}'),
        content: const Text('อยู่ในรัศมี 50 เมตร กรุณายืนยันผลการจัดเก็บ'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'fail'), child: const Text('ไม่สามารถจัดเก็บได้')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'done'), child: const Text('จัดเก็บแล้ว')),
        ],
      ),
    );
    if (r == 'done') {
      t.status = 'done';
    } else if (r == 'fail') {
      if (!mounted) return;
      final why = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(title: const Text('ระบุสาเหตุ'), children: [
          for (final s in ['ถังถูกกีดขวาง', 'ไม่มีขยะให้เก็บ', 'ถนนเข้าไม่ได้', 'อื่น ๆ'])
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, s), child: Text(s)),
        ]),
      );
      t.status = 'failed';
      t.reason = why ?? 'ไม่ระบุ';
    }
    app.changed();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('พนักงานเก็บขยะ')),
        body: ListenableBuilder(
          listenable: app,
          builder: (_, __) {
            final route = app.pendingRoute();
            final naive = app.points.where((p) => p.status == 'pending').map((p) => p.pos).toList();
            return ListView(padding: const EdgeInsets.all(12), children: [
              MapView(order: route),
              mapLegend(),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('เส้นทางแนะนำ (Clarke-Wright)', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(route.isEmpty ? 'เก็บครบทุกจุดแล้ว 🎉' : route.map((p) => p.label).join(' → ')),
                    if (route.isNotEmpty)
                      Text('ระยะทางเส้นตรงรวม ${(routeLen(route.map((p) => p.pos).toList(), app.truck) / 1000).toStringAsFixed(2)} กม. '
                          '(ลำดับเดิม ${(routeLen(naive, app.truck) / 1000).toStringAsFixed(2)} กม.)'),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: FilledButton.icon(onPressed: _step, icon: const Icon(Icons.navigation), label: const Text('จำลองขับไปจุดถัดไป (GPS)'))),
                const SizedBox(width: 8),
                OutlinedButton(
                    onPressed: () {
                      prompted.clear();
                      app.resetRound();
                    },
                    child: const Text('เริ่มรอบใหม่')),
              ]),
              pointList(),
            ]);
          },
        ),
      );
}

// ===================== Counter staff =====================
class CounterHome extends StatelessWidget {
  const CounterHome({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('เจ้าหน้าที่หน้าเคาน์เตอร์')),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          const ComplaintForm(channel: 'counter'),
          sectionTitle('คำร้องทั้งหมด'),
          ListenableBuilder(
            listenable: app,
            builder: (_, __) => Column(children: [for (final c in app.complaints.reversed) ComplaintTile(c)]),
          ),
        ]),
      );
}

// ===================== Fee officer =====================
class FeeOfficerHome extends StatefulWidget {
  const FeeOfficerHome({super.key});
  @override
  State<FeeOfficerHome> createState() => _FeeOfficerHomeState();
}

class _FeeOfficerHomeState extends State<FeeOfficerHome> {
  String village = villages.first;
  DateTime date = DateTime.now().add(const Duration(days: 3));

  Future<void> _pick() async {
    final d = await showDatePicker(context: context, initialDate: date, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (d != null) setState(() => date = d);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('เจ้าหน้าที่บัญชี/จัดเก็บค่าธรรมเนียม')),
        body: ListenableBuilder(
          listenable: app,
          builder: (_, __) => ListView(padding: const EdgeInsets.all(12), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('สร้างรอบจัดเก็บ & ประกาศกำหนดการ', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: village,
                    decoration: const InputDecoration(labelText: 'พื้นที่', border: OutlineInputBorder()),
                    items: [for (final v in villages) DropdownMenuItem(value: v, child: Text(v))],
                    onChanged: (v) => setState(() => village = v!),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(onPressed: _pick, icon: const Icon(Icons.event), label: Text('วันที่เข้าจัดเก็บ: ${fmtDate(date)}')),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                        child: FilledButton(
                            onPressed: () {
                              app.announce(village, date);
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ประกาศแล้ว (ป๊อปอัป + Push จำลอง)')));
                            },
                            child: const Text('ประกาศ'))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: OutlinedButton(
                            onPressed: () => app.announce(village, date, resched: true),
                            child: const Text('นัดใหม่ (ไม่พบผู้อยู่อาศัย)'))),
                  ]),
                ]),
              ),
            ),
            sectionTitle('สถานะรายครัวเรือน'),
            for (final h in app.households)
              Card(
                child: ExpansionTile(
                  title: Text('${h.no} • ${h.owner} (${h.village})'),
                  subtitle: Text(h.status),
                  childrenPadding: const EdgeInsets.all(12),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      for (final s in feeStatuses) ChoiceChip(label: Text(s), selected: h.status == s, onSelected: (_) => app.setFee(h, s)),
                    ]),
                    const SizedBox(height: 8),
                    for (final x in h.history) Text(x, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            sectionTitle('สรุปความคืบหน้า'),
            for (final s in feeStatuses) BarRow(s, app.households.where((h) => h.status == s).length, app.households.length),
          ]),
        ),
      );
}

// ===================== Supervisor =====================
class SupervisorHome extends StatelessWidget {
  const SupervisorHome({super.key});

  Widget _stat(String t, String v) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [Text(v, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), Text(t, style: const TextStyle(fontSize: 12), textAlign: TextAlign.center)]),
          ),
        ),
      );

  Widget _dash() {
    final done = app.points.where((p) => p.status == 'done').length;
    final failed = app.points.where((p) => p.status == 'failed').length;
    return ListView(padding: const EdgeInsets.all(12), children: [
      Row(children: [
        _stat('คำร้องทั้งหมด', '${app.complaints.length}'),
        _stat('จุดจัดเก็บแล้ว', '$done/${app.points.length}'),
        _stat('จัดเก็บไม่ได้', '$failed'),
      ]),
      sectionTitle('คำร้องตามสถานะ'),
      for (final s in complaintStatuses) BarRow(s, app.complaints.where((c) => c.status == s).length, math.max(1, app.complaints.length)),
      sectionTitle('ค่าธรรมเนียมตามสถานะ'),
      for (final s in feeStatuses) BarRow(s, app.households.where((h) => h.status == s).length, math.max(1, app.households.length)),
      sectionTitle('สรุปรายหมู่บ้าน'),
      for (final v in villages)
        ListTile(
          dense: true,
          leading: const Icon(Icons.location_on),
          title: Text(v),
          subtitle: Text('คำร้อง ${app.complaints.where((c) => c.village == v).length} • '
              'ค่าธรรมเนียมจัดเก็บแล้ว ${app.households.where((h) => h.village == v && h.status == "จัดเก็บแล้ว").length}/${app.households.where((h) => h.village == v).length}'),
        ),
      sectionTitle('ตำแหน่งรถ/จุดจัดเก็บ'),
      const MapView(),
      mapLegend(),
    ]);
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(title: const Text('หัวหน้าฝ่าย'), bottom: const TabBar(tabs: [Tab(text: 'แดชบอร์ด'), Tab(text: 'จัดการคำร้อง')])),
          body: ListenableBuilder(
            listenable: app,
            builder: (_, __) => TabBarView(children: [
              _dash(),
              ListView(padding: const EdgeInsets.all(12), children: [for (final c in app.complaints.reversed) ComplaintTile(c, editable: true)]),
            ]),
          ),
        ),
      );
}

// ===================== Admin (RBAC จำลอง) =====================
class AdminHome extends StatefulWidget {
  const AdminHome({super.key});
  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  static const roles = ['พนักงานเก็บขยะ', 'เจ้าหน้าที่เคาน์เตอร์', 'เจ้าหน้าที่บัญชี', 'หัวหน้าฝ่าย', 'ผู้ดูแลระบบ'];
  final users = {'somchai@maekha.go.th': 'พนักงานเก็บขยะ', 'malee@maekha.go.th': 'เจ้าหน้าที่บัญชี', 'boss@maekha.go.th': 'หัวหน้าฝ่าย'};

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('ผู้ดูแลระบบ: ผู้ใช้และสิทธิ์')),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          const Text('Prototype: ในระบบจริงใช้ Supabase Auth + Row Level Security'),
          for (final e in users.entries)
            Card(
              child: ListTile(
                leading: const Icon(Icons.badge),
                title: Text(e.key),
                trailing: DropdownButton<String>(
                  value: e.value,
                  items: [for (final r in roles) DropdownMenuItem(value: r, child: Text(r))],
                  onChanged: (v) => setState(() => users[e.key] = v!),
                ),
              ),
            ),
        ]),
      );
}
