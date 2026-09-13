import urllib.request
import gzip
import zipfile
import io
import csv

headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9'
}

def test_contract_file():
    # Test for June 11, 2026 (yesterday/recent trading day)
    date_str = "11062026"
    url = f"https://nsearchives.nseindia.com/content/fo/NSE_FO_contract_{date_str}.csv.gz"
    print(f"Fetching contract file: {url}")
    
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req) as response:
            compressed_data = response.read()
            print(f"Successfully downloaded {len(compressed_data)} bytes.")
            with gzip.open(io.BytesIO(compressed_data), 'rt') as f:
                reader = csv.reader(f)
                header = next(reader)
                print("Contract File Header:", header)
                # print first 3 rows
                for i in range(3):
                    try:
                        print(f"Row {i}:", next(reader))
                    except StopIteration:
                        break
    except Exception as e:
        print(f"Error downloading/parsing contract file: {e}")

def test_bhavcopy():
    # Test for June 11, 2026
    date_str = "20260611"
    url = f"https://nsearchives.nseindia.com/content/fo/BhavCopy_NSE_FO_0_0_0_{date_str}_F_0000.csv.zip"
    print(f"Fetching bhavcopy: {url}")
    
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req) as response:
            zip_data = response.read()
            print(f"Successfully downloaded {len(zip_data)} bytes.")
            with zipfile.ZipFile(io.BytesIO(zip_data)) as z:
                # Find the csv filename inside the zip
                csv_filename = [name for name in z.namelist() if name.endswith('.csv')][0]
                print(f"Found CSV in zip: {csv_filename}")
                with z.open(csv_filename) as f:
                    # read as text
                    text_data = f.read().decode('utf-8')
                    reader = csv.reader(io.StringIO(text_data))
                    header = next(reader)
                    print("Bhavcopy Header:", header)
                    # print first 3 rows
                    for i in range(3):
                        try:
                            print(f"Row {i}:", next(reader))
                        except StopIteration:
                            break
    except Exception as e:
        print(f"Error downloading/parsing bhavcopy: {e}")

if __name__ == '__main__':
    test_contract_file()
    print("-" * 50)
    test_bhavcopy()
