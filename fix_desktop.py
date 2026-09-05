import io

filepath = 'lib/features/partner_dashboard/presentation/partner_dashboard_desktop.dart'
with io.open(filepath, 'r', encoding='utf-8') as f:
    content = f.read()

# Add incoming var
content = content.replace(
    "final inBay = allJobs.where((j) => j.status == '5_admitted' || j.status == '6_in_progress').toList();",
    "final incoming = allJobs.where((j) => j.status == '3_booked' || j.status == '4_paid').toList();\n    final inBay = allJobs.where((j) => j.status == '5_admitted' || j.status == '6_in_progress').toList();"
)

# Add Swimlane
swimlane_code = """                                    _Swimlane(
                                      title: 'New Bookings',
                                      color: _blue500,
                                      jobs: incoming,
                                      controller: controller,
                                    ),
                                    const SizedBox(width: 16),
                                    _Swimlane(
                                      title: 'Body Repair / Frame',"""

content = content.replace(
    """                                    _Swimlane(
                                      title: 'Body Repair / Frame',""",
    swimlane_code
)

# Update _statusColor
content = content.replace(
    "if (status.contains('paid') || status.contains('booked')) return _blue500;",
    "if (status.contains('paid') || status.contains('booked')) return _blue500;"
)

# Fix Advance Button text
btn_code = """label: Text((job.status == '3_booked' || job.status == '4_paid') ? 'Admit Vehicle' : 'Advance', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),"""
content = content.replace(
    "label: const Text('Advance', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),",
    btn_code
)

with io.open(filepath, 'w', encoding='utf-8') as f:
    f.write(content)
