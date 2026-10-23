# Company Logo Fetcher

This script automatically fetches company logos from companieslogo.com for all companies listed in your CSV file.

## Features

- Reads companies from `company-list.csv`
- Removes country information in parentheses (e.g., "PFIZER (FRANCE)" → "PFIZER")
- Handles companies separated by "/" (e.g., "COMPANY A / COMPANY B")
- Avoids downloading duplicate logos for the same company
- Tries to download SVG format logos from companieslogo.com
- Generates a reference CSV mapping companies to their logos

## Prerequisites

Make sure you have Python 3 installed with the following libraries:

```bash
pip install requests beautifulsoup4
```

## Usage

1. Make sure `company-list.csv` is in the "Lab Logos" folder
2. Run the script:

```bash
python3 fetch_logos.py
```

3. The script will:
   - Create a `company-logos/` folder with all downloaded SVG files
   - Create `company-logos-reference.csv` with the mapping

## Output Files

### company-logos/ folder
Contains all downloaded SVG logo files, named using lowercase slugs of company names.

Example files:
- `pfizer.svg`
- `sanofi.svg`
- `novartis.svg`

### company-logos-reference.csv
CSV file with the following columns:
- `original_name`: Original company name from input CSV (including country)
- `company_name`: Cleaned company name (without country)
- `logo_filename`: Name of the downloaded SVG file
- `logo_path`: Relative path to the logo file
- `status`: "downloaded" or "not_found"
- `source`: Where the logo was found (e.g., "companieslogo.com")

## How It Works

1. **Name Cleaning**: Removes country information and extra whitespace
2. **Slug Generation**: Converts company names to URL-friendly format
   - Removes common terms (Limited, Inc, Pharma, etc.)
   - Converts to lowercase
   - Replaces spaces with hyphens
3. **Logo Download**: Tries multiple URL patterns on companieslogo.com
4. **Deduplication**: Tracks processed companies to avoid redundant downloads

## Notes

- CompaniesLogo.com primarily hosts logos of publicly traded companies
- Not all pharmaceutical laboratories may be available
- The script adds a small delay between requests to be respectful to the server
- Logos are downloaded in SVG format for best quality and scalability

## Troubleshooting

If logos are not found:
- The company might not be publicly traded
- The company name might be too different from what's on companieslogo.com
- You may need to manually search for and add those logos

## Manual Additions

For logos not found automatically, you can:
1. Manually search for the logo
2. Save it as an SVG file in the `company-logos/` folder
3. Update the corresponding row in `company-logos-reference.csv`
