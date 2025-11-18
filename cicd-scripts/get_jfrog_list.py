
import requests
import csv
import sys

def get_ear_info(api_key, base_url, csv_file):
    headers = {
        "X-JFrog-Art-Api": api_key
    }

    response = requests.get(base_url, headers=headers)

    if response.status_code == 200:
        try:
            data = response.json()
            with open(csv_file, mode='a', newline='') as file:
                writer = csv.writer(file)
                for item in data["children"]:
                    if item["folder"]:
                        interface_name = item["uri"]
                        interface_url = f"{base_url}{interface_name}/Development/Dev-1/"
                        get_ear_info(api_key, interface_url, csv_file)
                    else:
                        ear_name = item["uri"].split("/")[-1]
                        ear_size = item["size"]
                        writer.writerow([base_url, ear_name, ear_size])
        except requests.exceptions.JSONDecodeError as e:
            print(f"Error: Unable to parse JSON response. {e}")
            print(f"Raw response: {response.text}")
    else:
        print(f"Error: Unable to retrieve data. Status code {response.status_code}")

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("Usage: python script.py <api_key> <base_url> <output_csv>")
        sys.exit(1)
        
    api_key = sys.argv[1]
    base_url = sys.argv[2]
    output_csv = sys.argv[3]
    
    with open(output_csv, mode='w', newline='') as file:
        writer = csv.writer(file)
        writer.writerow(["Interface", "Ear Name", "Size"])
    
    get_ear_info(api_key, base_url, output_csv)
