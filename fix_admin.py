import io
filepath = "lib/features/admin_central/presentation/admin_job_assignment_screen.dart"
with io.open(filepath, "r", encoding="utf-8") as f:
    lines = f.readlines()

lines[65] = "      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error assigning job'), backgroundColor: Colors.red));\n"
lines[118] = "                                      Text('Vehicle: ' + str(v.get('brand', '')) + ' ' + str(v.get('model', '')), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textColor)),\n"
lines[119] = "                                      Text('Customer: ' + str(p.get('full_name', '')), style: TextStyle(color: textColor)),\n"
lines[124] = "                                        child: Text('Location: ' + str(jobArea), style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),\n"

for i in range(len(lines)):
    if "DropdownMenuItem(value: pt[" in lines[i]:
        lines[i] = lines[i].replace("Text('\\ (\\)')", "Text(pt['shop_name'].toString() + ' (' + pt['service_area'].toString() + ')')")
        lines[i] = lines[i].replace("Text('\\\ (\\\)')", "Text(pt['shop_name'].toString() + ' (' + pt['service_area'].toString() + ')')")

with io.open(filepath, "w", encoding="utf-8") as f:
    f.writelines(lines)
