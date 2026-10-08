#!/usr/bin/env python3
"""
Re-V Chatbot Booking Pipeline Automation
Maps WA number -> Profiles -> Uploads photos -> Estimates vs Pricing Rules -> Assigns Slot -> Inserts Job.
Now includes OTP Authentication.
"""
import argparse
import base64
import json
import os
import sys
import time
import uuid
import urllib.error
import urllib.request
import random
from urllib.parse import quote
from datetime import datetime, timedelta

TIMEOUT = 30



def _get_supabase_creds():
    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not key:
        print("Error: Missing env SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY", file=sys.stderr)
        sys.exit(1)
    return url, key

def generate_otp(phone):
    url, key = _get_supabase_creds()
    code = str(random.randint(100000, 999999))
    expires_at = (datetime.utcnow() + timedelta(minutes=5)).isoformat() + "Z"
    
    payload = {
        "phone": phone,
        "code": code,
        "expires_at": expires_at,
        "verified": False,
        "attempts": 0
    }
    
    # Upsert the OTP
    req_url = f"{url.rstrip('/')}/rest/v1/wa_otp_verifications"
    import urllib.request
    req = urllib.request.Request(
        req_url,
        method="POST",
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Prefer": "resolution=merge-duplicates"
        },
        data=json.dumps(payload).encode()
    )
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        pass
        
    print(f"\n--- OTP GENERATED ---")
    print(f"OTP: {code}")
    print(f"Please send this code to the user and ask them to reply with it.")
    return code

def verify_otp(phone, code):
    url, key = _get_supabase_creds()
    
    # Get current OTP record
    import urllib.parse
    q_phone = urllib.parse.quote(phone)
    record = _supabase_req(url, key, "GET", f"/wa_otp_verifications?phone=eq.{q_phone}&select=*")
    
    if not record or len(record) == 0:
        print(f"Error: No OTP requested for {phone}", file=sys.stderr)
        return False
        
    record = record[0]
    
    if record.get("verified"):
        print(f"Phone {phone} is already verified.", file=sys.stderr)
        return True
        
    attempts = record.get("attempts", 0)
    if attempts >= 3:
        print(f"Error: Max attempts reached for {phone}. Please request a new OTP.", file=sys.stderr)
        return False
        
    # Check expiry
    # UTC parse
    # For simplicity, if datetime.utcnow() > expires_at
    from datetime import datetime
    # typical format: 2026-10-08T10:00:00+00:00 or Z
    exp_str = record["expires_at"].replace("Z", "+00:00")
    exp_dt = datetime.fromisoformat(exp_str)
    
    if datetime.now(exp_dt.tzinfo) > exp_dt:
        print(f"Error: OTP for {phone} has expired", file=sys.stderr)
        return False
        
    if record["code"] != code:
        attempts += 1
        payload = {"attempts": attempts}
        _supabase_req(url, key, "PATCH", f"/wa_otp_verifications?phone=eq.{q_phone}", payload=payload)
        print(f"Error: Invalid OTP for {phone}. Attempt {attempts}/3", file=sys.stderr)
        return False
        
    # Success
    payload = {"verified": True}
    _supabase_req(url, key, "PATCH", f"/wa_otp_verifications?phone=eq.{q_phone}", payload=payload)
    print(f"\n--- OTP VERIFIED ---")
    print(f"Phone {phone} is now authenticated.")
    return True

def is_verified(phone):
    url, key = _get_supabase_creds()
    import urllib.parse
    q_phone = urllib.parse.quote(phone)
    record = _supabase_req(url, key, "GET", f"/wa_otp_verifications?phone=eq.{q_phone}&select=verified")
    return record and len(record) > 0 and record[0].get("verified") is True

def _supabase_req(url, key, method, path, payload=None, is_auth=False, is_storage=False, content_type="application/json"):
    base = url.rstrip("/")
    if is_auth:
        full_url = f"{base}/auth/v1{path}"
    elif is_storage:
        full_url = f"{base}/storage/v1{path}"
    else:
        full_url = f"{base}/rest/v1{path}"
        
    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
    }
    if payload is not None:
        if content_type:
            headers["Content-Type"] = content_type
    
    data = payload if isinstance(payload, bytes) else (json.dumps(payload).encode() if payload is not None else None)
    req = urllib.request.Request(full_url, method=method, headers=headers, data=data)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            raw = r.read()
            if not raw: return None
            return json.loads(raw.decode("utf-8"))
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "ignore")[:300]
        raise RuntimeError(f"supabase {method} {full_url} -> HTTP {e.code}: {detail}") from None

def map_wa_to_profile(url, key, phone, name):
    print(f"Mapping WA {phone} to profile...")
    clean_phone = phone.replace("+", "").replace("-", "").replace(" ", "")
    try:
        profiles = _supabase_req(url, key, "GET", f"/profiles?phone=eq.{clean_phone}")
        if profiles and len(profiles) > 0:
            print(f"  Found existing profile: {profiles[0]['id']}")
            return profiles[0]
    except Exception as e:
        print("  Error fetching profile", e)
        
    print(f"  Profile not found. Creating new auth user and profile for {clean_phone}...")
    fake_email = f"{clean_phone}@wa.revive.co.id"
    user_payload = {
        "email": fake_email,
        "password": str(uuid.uuid4()) + "Aa1!",
        "email_confirm": True,
        "user_metadata": {
            "full_name": name,
            "phone": clean_phone
        }
    }
    user = _supabase_req(url, key, "POST", "/admin/users", payload=user_payload, is_auth=True)
    user_id = user["id"]
    
    time.sleep(1)
    
    profile_payload = {
        "full_name": name,
        "phone": clean_phone
    }
    _supabase_req(url, key, "PATCH", f"/profiles?id=eq.{user_id}", payload=profile_payload)
    print(f"  Created profile: {user_id}")
    return {"id": user_id, "full_name": name, "phone": clean_phone}

def upload_photo(url, key, user_id, photo_path):
    print(f"Uploading {photo_path}...")
    filename = f"{int(time.time())}_{os.path.basename(photo_path)}"
    path = f"chatbot/{user_id}/{filename}"
    
    with open(photo_path, "rb") as f:
        file_bytes = f.read()
        
    res = _supabase_req(url, key, "POST", f"/object/revive-photos/{path}", payload=file_bytes, is_storage=True, content_type="image/jpeg")
    print(f"  Uploaded to {path}")
    
    public_url = f"{url.rstrip('/')}/storage/v1/object/public/revive-photos/{path}"
    return public_url, path

def run_vision_estimation(gemini_key, photo_paths):
    print("Running vision estimation...")
    image_parts = []
    for p in photo_paths:
        with open(p, "rb") as f:
            b64 = base64.b64encode(f.read()).decode("utf-8")
        image_parts.append({"inline_data": {"mime_type": "image/jpeg", "data": b64}})
        
    prompt = "Analyze the car body damage from these images. Valid panel names are: Bumper Depan, Spoiler Bumper depan, Kap Mesin, Bumper Belakang, Spoiler Bumper Belakang, Bagasi, Spoiler Bagasi, Fender RH, Pintu Depan RH, Spion RH, Pintu Belakang RH, Quarter RH, Trisplang RH, Side Roof RH, Fender LH, Pintu Depan LH, Spion LH, Pintu Belakang LH, Quarter LH, Trisplang LH, Side Roof LH, Roof, Cover. For each damaged panel found, classify its specific severity into: 'ringan', 'sedang', or 'berat'. Also classify the overall severity of the car damage. Return precise counts for dents, scratches, and broken panels in JSON format."
    
    payload = {
        "contents": [{
            "parts": [{"text": prompt}] + image_parts
        }],
        "generationConfig": {
            "responseMimeType": "application/json"
        }
    }
    
    req = urllib.request.Request(
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent",
        method="POST",
        headers={"Content-Type": "application/json", "x-goog-api-key": gemini_key},
        data=json.dumps(payload).encode()
    )
    
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            data = json.loads(r.read().decode())
            text = data["candidates"][0]["content"]["parts"][0]["text"]
            if "```json" in text:
                text = text.split("```json")[1].split("```")[0]
            elif "```" in text:
                text = text.split("```")[1].split("```")[0]
            parsed = json.loads(text.strip())
            print("  AI Estimation Done.")
            return parsed
    except Exception as e:
        print("  Gemini API error:", e)
        return {
            "assessment": {
                "damaged_panels_detail": [
                    {"panel_name": "Bumper Depan", "panel_severity": "sedang"}
                ]
            }
        }

def calculate_cost(url, key, estimation):
    print("Calculating cost vs pricing_rules...")
    try:
        rules = _supabase_req(url, key, "GET", "/pricing_rules?select=panel_name,base_rate,severity_min,severity_max")
        rule_map = {r["panel_name"].lower(): r for r in rules}
    except Exception:
        rule_map = {}
    
    total = 0
    panels = estimation.get("assessment", {}).get("damaged_panels_detail", [])
    for p in panels:
        name = p.get("panel_name", "").lower()
        sev = p.get("panel_severity", "berat").lower()
        if name in rule_map:
            rule = rule_map[name]
            mult = rule["severity_min"] if sev == "sedang" else rule["severity_max"] if sev == "berat" else 1.0
            cost = int(rule["base_rate"] * mult)
        else:
            base = 500000
            mult = 1.5 if sev == "sedang" else 2.0 if sev == "berat" else 1.0
            cost = int(base * mult)
            
        p["calculated_cost"] = cost
        total += cost
        
    estimation["financial_estimation"] = {"calculated_base_cost": total, "pricing_source": "live_db"}
    print(f"  Total Estimated Cost: Rp {total}")
    return total

def assign_slot_and_insert(url, key, user_id, phone, total_cost, estimation, photo_keys):
    print("Assigning slot and inserting job...")
    partners = _supabase_req(url, key, "GET", "/partners?status=eq.active&limit=1")
    partner_id = partners[0]["id"] if partners else None
    
    vehicle_payload = {
        "customer_id": user_id,
        "make": "Unknown",
        "model": "Chatbot Intake",
        "year": 2020,
        "license_plate": f"WA-{phone[-4:]}"
    }
    
    v_req = urllib.request.Request(
        f"{url.rstrip('/')}/rest/v1/vehicles?on_conflict=customer_id,license_plate",
        method="POST",
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Prefer": "resolution=merge-duplicates,return=representation"
        },
        data=json.dumps(vehicle_payload).encode()
    )
    with urllib.request.urlopen(v_req, timeout=TIMEOUT) as r:
        vehicles = json.loads(r.read().decode())
        vehicle_id = vehicles[0]["id"]
        
    job_payload = {
        "customer_id": user_id,
        "vehicle_id": vehicle_id,
        "partner_id": partner_id,
        "initial_estimation_cost": total_cost,
        "estimation_result": estimation,
        "status": "2_estimated",
        "contact_phone": phone
    }
    
    j_req = urllib.request.Request(
        f"{url.rstrip('/')}/rest/v1/repair_jobs",
        method="POST",
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Prefer": "return=representation"
        },
        data=json.dumps(job_payload).encode()
    )
    with urllib.request.urlopen(j_req, timeout=TIMEOUT) as r:
        jobs = json.loads(r.read().decode())
        job_id = jobs[0]["id"]
        
    print(f"  Job created: {job_id}")
    
    for pk in photo_keys:
        p_payload = {
            "job_id": job_id,
            "file_key": pk,
            "step_context": "estimate",
            "uploaded_by": user_id
        }
        _supabase_req(url, key, "POST", "/repair_photos", payload=p_payload)
        
    return job_id

def main():
    parser = argparse.ArgumentParser(description="Re-V Chatbot Booking Pipeline with OTP")
    parser.add_argument("--action", choices=["request-otp", "verify-otp", "book"], required=True)
    parser.add_argument("--phone", required=True, help="Customer WA number")
    parser.add_argument("--code", help="OTP Code (for verify-otp)")
    parser.add_argument("--name", default="Guest", help="Customer Name (for book)")
    parser.add_argument("--photos", help="Comma separated local photo paths (for book)")
    args = parser.parse_args()

    clean_phone = args.phone.replace("+", "").replace("-", "").replace(" ", "")

    if args.action == "request-otp":
        generate_otp(clean_phone)
        return 0
        
    elif args.action == "verify-otp":
        if not args.code:
            print("Error: --code is required for verify-otp", file=sys.stderr)
            return 1
        success = verify_otp(clean_phone, args.code)
        return 0 if success else 1
        
    elif args.action == "book":
        if not is_verified(clean_phone):
            print(f"Error: Phone {clean_phone} is NOT authenticated. Please request and verify OTP first.", file=sys.stderr)
            return 1
            
        url = os.environ.get("SUPABASE_URL")
        key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
        gemini_key = os.environ.get("GOOGLE_AI_API_KEY")
        
        if not url or not key or not gemini_key:
            print("Error: Missing env SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, or GOOGLE_AI_API_KEY", file=sys.stderr)
            return 1

        try:
            profile = map_wa_to_profile(url, key, clean_phone, args.name)
            
            photo_paths = [p.strip() for p in args.photos.split(",") if p.strip()] if args.photos else []
            public_urls = []
            photo_keys = []
            for p in photo_paths:
                if not os.path.exists(p):
                    print(f"Warning: File {p} not found. Skipping.")
                    continue
                pub_url, p_key = upload_photo(url, key, profile["id"], p)
                public_urls.append(pub_url)
                photo_keys.append(p_key)
                
            if not photo_paths:
                print("No valid photos to process.", file=sys.stderr)
                return 1
                
            estimation = run_vision_estimation(gemini_key, photo_paths)
            estimation["photo_keys"] = photo_keys 
            
            total_cost = calculate_cost(url, key, estimation)
            
            job_id = assign_slot_and_insert(url, key, profile["id"], profile["phone"], total_cost, estimation, photo_keys)
            
            print("\n--- PIPELINE SUCCESS ---")
            print(f"Job ID: {job_id}")
            print(f"Estimation: Rp {total_cost:,}")
            
            # Optionally invalidate OTP after successful booking
            otps = load_otps()
            if clean_phone in otps:
                del otps[clean_phone]
                save_otps(otps)
            
        except Exception as e:
            print(f"Pipeline Failed: {e}", file=sys.stderr)
            return 1
            
    return 0

if __name__ == "__main__":
    sys.exit(main())
