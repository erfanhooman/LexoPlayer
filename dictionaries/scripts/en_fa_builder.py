import sqlite3
import requests
import json
import os
import warnings
from tqdm import tqdm

# Silence the macOS LibreSSL warnings
warnings.filterwarnings("ignore", category=UserWarning, module='urllib3')

def build_generic_db():
    print("🚀 Starting LexoPlayer Persian Generic-13 Dictionary Build...")
    db_name = "english_to_persian_bilangual.db"
    
    # Clean old database files safely
    if os.path.exists(db_name):
        try:
            os.remove(db_name)
        except PermissionError:
            print(f"❌ Error: {db_name} is currently open. Close it first!")
            return

    # Connect and initialize database schema
    conn = sqlite3.connect(db_name)
    cursor = conn.cursor()
    cursor.execute("""
    CREATE TABLE entries (
        word TEXT PRIMARY KEY,
        localized_text TEXT
    );
    """)
    cursor.execute("CREATE INDEX idx_entries_word ON entries(word);")

    # Define all alphabet split files inside the generic-13 folder
    alphabet_files = [
        "-", "..", "0", "1", "2", "3", "4", "5", "7", "8", "=",
        "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", 
        "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"
    ]
    
    # Target URL updated strictly to generic-13
    base_raw_url = "https://raw.githubusercontent.com/VahidN/EnglishToPersianDictionaries/master/Dictionaries/generic-13"
    
    batch_data = []
    total_extracted = 0

    print(f"📥 Downloading and parsing {len(alphabet_files)} dictionary subsets from generic-13...")
    
    for item in tqdm(alphabet_files, desc="Downloading alphabet subsets", unit="file"):
        file_url = f"{base_raw_url}/{item}.json"
        
        try:
            response = requests.get(file_url)
            if response.status_code == 404:
                continue
            response.raise_for_status()
            
            # Decode using utf-8-sig to clear the invisible Windows BOM signature
            clean_text = response.content.decode('utf-8-sig')
            
            # Parse text layout into JSON
            data = json.loads(clean_text)
            words_list = data.get("Words", [])
            
            for word_entry in words_list:
                eng_word = word_entry.get("EnglishWord", "").strip().lower()
                meanings = word_entry.get("Meanings", [])
                
                if eng_word and meanings:
                    # Join multiple Persian dictionary definitions cleanly
                    persian_text = ", ".join([m.strip() for m in meanings if m.strip()])
                    
                    if persian_text:
                        batch_data.append((eng_word, persian_text))
                        total_extracted += 1
                        
        except Exception as e:
            print(f"\n⚠️ Error processing {item}.json: {e}")
            continue

    # Commit to SQLite in efficient chunks
    print(f"\n💾 Writing {total_extracted} core words to your local SQLite database...")
    chunk_size = 5000
    total_inserted = 0
    
    if batch_data:
        for i in range(0, len(batch_data), chunk_size):
            chunk = batch_data[i:i + chunk_size]
            cursor.executemany("INSERT OR IGNORE INTO entries (word, localized_text) VALUES (?, ?)", chunk)
            total_inserted += cursor.rowcount
            
    conn.commit()
    conn.close()
    
    print("\n" + "="*45)
    print("✅ SUCCESS! Your Massive Core Word Database is ready.")
    print(f"📍 Location: {os.path.abspath(db_name)}")
    print(f"📊 Total vocabulary terms saved: {total_inserted}")
    print("="*45)

if __name__ == "__main__":
    build_generic_db()