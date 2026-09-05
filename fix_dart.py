import io

path = 'lib/features/customer_app/home/presentation/customer_landing_screen.dart'
content = io.open(path, 'r', encoding='utf-8').read()
content = content.replace("str(job.get('id', ''))[0:8]", "job['id'].toString().substring(0, 8)")
content = content.replace("statusStr.replace('_', ' ').upper()", "statusStr.replaceAll('_', ' ').toUpperCase()")
content = content.replace("str(job.get('created_at', ''))[:10]", "job['created_at'].toString().substring(0, 10)")
content = content.replace("str(job.get('id', ''))", "job['id'].toString()")
io.open(path, 'w', encoding='utf-8').write(content)
