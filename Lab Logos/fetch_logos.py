#!/usr/bin/env python3
"""
Script to fetch company logos
- First tries companieslogo.com (for publicly traded companies)
- Falls back to Brandfetch using new CDN endpoint
"""

import csv
import os
import re
import requests
import time
from urllib.parse import quote

API_KEY = "1idJK0qWUL8Yi2cpcNZ"  # Brandfetch API key

def clean_company_name(name):
    """Remove country info in parentheses and clean up the company name"""
    name = re.sub(r'\s*\([^)]*\)', '', name)
    name = name.strip()
    return name

def extract_companies(company_string):
    """Extract individual companies from string (handle / separator)"""
    companies = []
    if '/' in company_string:
        parts = company_string.split('/')
        for part in parts:
            cleaned = clean_company_name(part)
            if cleaned:
                companies.append(cleaned)
    else:
        cleaned = clean_company_name(company_string)
        if cleaned:
            companies.append(cleaned)
    return companies

def company_name_to_slug(company_name):
    """Convert company name to URL slug format"""
    slug = company_name.lower()
    
    removals = [
        r'\b(laboratoire|laboratoires|lab|laboratories)\b',
        r'\b(pharma|pharmaceutical|pharmaceuticals|pharmaceutique)\b',
        r'\b(limited|ltd|llc|inc|corp|corporation|s\.?p\.?a\.?|gmbh|ag|bv|sa|sas)\b',
        r'\b(international|europe|france|deutschland)\b',
        r'\b(healthcare|health\s*care|sante|medical)\b',
        r'\b(group|groupe|holding)\b'
    ]
    
    for pattern in removals:
        slug = re.sub(pattern, '', slug, flags=re.IGNORECASE)
    
    slug = re.sub(r'[^a-z0-9\s-]', '', slug)
    slug = re.sub(r'\s+', '-', slug)
    slug = re.sub(r'-+', '-', slug)
    slug = slug.strip('-')
    
    return slug

def try_download_from_companieslogo(company_name):
    """Try to download logo from companieslogo.com"""
    slug = company_name_to_slug(company_name)
    
    if not slug:
        return None
    
    urls = [
        f"https://companieslogo.com/img/company/{slug}_logo.svg",
        f"https://companieslogo.com/img/company/{slug}_icon.svg",
        f"https://companieslogo.com/img/company/{slug}.svg",
    ]
    
    words = slug.split('-')
    if len(words) > 1:
        urls.append(f"https://companieslogo.com/img/company/{words[0]}_logo.svg")
    
    for url in urls:
        try:
            response = requests.get(url, timeout=5, allow_redirects=True)
            if response.status_code == 200 and len(response.content) > 100:
                content_type = response.headers.get('content-type', '')
                if 'svg' in content_type.lower() or b'<svg' in response.content[:500]:
                    return response.content, "svg"
        except:
            continue
    
    return None, None

def brandfetch_search(company_name):
    """
    Search Brandfetch for the best matching domain.
    """
    query = quote(company_name)
    url = f"https://api.brandfetch.io/v2/search/{query}?c={API_KEY}"

    try:
        r = requests.get(url, timeout=10)
        if r.status_code != 200:
            return None, None

        data = r.json()
        if not isinstance(data, list) or len(data) == 0:
            return None, None

        best = data[0]
        domain = best.get("domain")
        brand_id = best.get("brandId")

        return domain, brand_id
    except:
        return None, None

def brandfetch_download_logo(domain):
    """
    Download logo using the new Brandfetch CDN endpoint:
    https://cdn.brandfetch.io/{domain}/w/512/h/90/theme/light/logo?c=API_KEY
    """

    if not domain:
        return None, None

    url = f"https://cdn.brandfetch.io/{domain}/w/512/h/90/theme/light/logo?c={API_KEY}"

    try:
        r = requests.get(url, timeout=10)

        if r.status_code != 200:
            return None, None

        content_type = r.headers.get("Content-Type", "").lower()

        if "text/html" in content_type:
            return None, None

        if len(r.content) < 200:
            return None, None

        ext = {
            "image/svg+xml": "svg",
            "image/png": "png",
            "image/jpeg": "jpg",
            "image/webp": "webp"
        }.get(content_type, "img")

        return r.content, ext

    except:
        return None, None

def save_logo(company_name, content, extension, output_dir):
    """
    Save the logo using correct file extension.
    """
    safe_filename = re.sub(r'[^a-z0-9\s-]', '', company_name.lower())
    safe_filename = re.sub(r'\s+', '-', safe_filename)
    safe_filename = re.sub(r'-+', '-', safe_filename).strip('-')

    filename = f"{safe_filename}.{extension}"
    filepath = os.path.join(output_dir, filename)

    with open(filepath, 'wb') as f:
        f.write(content)

    return filepath, filename

def process_company(company_name, output_dir, processed_companies):
    """Process a single company"""
    if company_name in processed_companies:
        return processed_companies[company_name]
    
    print(f"  Processing: {company_name}")
    
    # 1. Try companieslogo.com
    content, ext = try_download_from_companieslogo(company_name)
    
    if content:
        filepath, filename = save_logo(company_name, content, ext, output_dir)
        print(f"    ✓ Downloaded from companieslogo.com ({ext.upper()})")
        result = {
            'logo_filename': filename,
            'logo_path': f"company-logos/{filename}",
            'status': 'downloaded',
            'source': 'companieslogo.com'
        }
        processed_companies[company_name] = result
        return result
    
    print("    ✗ Not found on companieslogo.com, trying Brandfetch...")

    # 2. Search domain in Brandfetch
    domain, brand_id = brandfetch_search(company_name)

    if not domain:
        print("    ✗ No domain found")
        result = {
            'logo_filename': '',
            'logo_path': '',
            'status': 'not_found',
            'source': 'brandfetch'
        }
        processed_companies[company_name] = result
        return result

    print(f"    → Domain: {domain}")

    # 3. Download from Brandfetch CDN
    content, ext = brandfetch_download_logo(domain)

    if content:
        filepath, filename = save_logo(company_name, content, ext, output_dir)
        print(f"    ✓ Logo downloaded from Brandfetch ({ext.upper()})")
        result = {
            'logo_filename': filename,
            'logo_path': f"company-logos/{filename}",
            'status': 'downloaded',
            'source': 'brandfetch'
        }
    else:
        print("    ✗ Logo not found on Brandfetch CDN")
        result = {
            'logo_filename': '',
            'logo_path': '',
            'status': 'not_found',
            'source': 'brandfetch'
        }

    processed_companies[company_name] = result
    return result

def main():
    base_dir = "/Users/emile.pommier/Developpment/DreamFlow/Medigo/Lab Logos"
    input_csv = os.path.join(base_dir, "company-list.csv")
    output_dir = os.path.join(base_dir, "company-logos")
    output_csv = os.path.join(base_dir, "company-logos-reference.csv")
    
    os.makedirs(output_dir, exist_ok=True)
    
    processed_companies = {}
    results = []
    
    with open(input_csv, 'r', encoding='utf-8') as f:
        content = f.read()
        lines = content.strip().split('\n')
    
    total = len(lines) - 1
    print(f"Processing {total} entries...\n")
    
    for i, line in enumerate(lines[1:], 1):
        original_name = line.strip()
        if not original_name:
            continue
        
        print(f"[{i}/{total}] {original_name}")
        companies = extract_companies(original_name)
        
        for company in companies:
            result = process_company(company, output_dir, processed_companies)
            
            results.append({
                'original_name': original_name,
                'company_name': company,
                **result
            })
        
        time.sleep(0.2)
    
    with open(output_csv, 'w', encoding='utf-8', newline='') as f:
        fieldnames = ['original_name', 'company_name', 'logo_filename', 'logo_path', 'status', 'source']
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(results)
    
    downloaded = sum(1 for r in results if r['status'] == 'downloaded')
    not_found = sum(1 for r in results if r['status'] == 'not_found')
    unique = len(processed_companies)
    
    print("\n" + "="*70)
    print("SUMMARY")
    print("="*70)
    print(f"Total unique companies: {unique}")
    print(f"Logos downloaded: {downloaded} ({downloaded/unique*100:.1f}%)")
    print(f"Logos not found: {not_found} ({not_found/unique*100:.1f}%)")
    print(f"\nOutput CSV: {output_csv}")
    print(f"Logos directory: {output_dir}")
    print("="*70)

if __name__ == "__main__":
    main()
