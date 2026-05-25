import sqlite3
import requests
import json
import os
import warnings
from tqdm import tqdm

# Silence the macOS LibreSSL warnings
warnings.filterwarnings("ignore", category=UserWarning, module='urllib3')

def build_combined_db():
    print("🚀 Starting LexoPlayer Persian Combined (Generic + Idioms) Dictionary Build...")
    db_name = "english_to_persian_bilingual.db"
    
    # Clean old database files safely
    if os.path.exists(db_name):
        try:
            os.remove(db_name)
        except PermissionError:
            print(f"❌ Error: {db_name} is currently open. Close it first, my lord!")
            return

    # Initialize master ledger to hold words before committing to the realm's database
    # Format: { "word": ["meaning1", "meaning2", ...] }
    vocabulary_ledger = {}

    # Define the alphabet split files and the specific collections we wish to harvest
    alphabet_files = [
        "-", "..", "0", "1", "2", "3", "4", "5", "7", "8", "=",
        "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", 
        "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"
    ]
    
    collections = ["generic-13", "idioms-1"]
    base_raw_url = "https://raw.githubusercontent.com/VahidN/EnglishToPersianDictionaries/master/Dictionaries"
    
    for collection in collections:
        print(f"\n📥 Gathering knowledge from the '{collection}' collection...")
        
        for item in tqdm(alphabet_files, desc=f"Downloading {collection} subsets", unit="file"):
            file_url = f"{base_raw_url}/{collection}/{item}.json"
            
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
                        # Ensure the word exists in our master ledger
                        if eng_word not in vocabulary_ledger:
                            vocabulary_ledger[eng_word] = []
                            
                        # Add meanings, checking for duplicates so we don't repeat translations
                        for m in meanings:
                            clean_meaning = m.strip()
                            if clean_meaning and clean_meaning not in vocabulary_ledger[eng_word]:
                                vocabulary_ledger[eng_word].append(clean_meaning)
                            
            except Exception as e:
                print(f"\n⚠️ Error processing {collection}/{item}.json: {e}")
                continue

    # Prepare data for the database
    batch_data = []
    for word, meanings in vocabulary_ledger.items():
        persian_text = ", ".join(meanings)
        batch_data.append((word, persian_text))

    print(f"\n💾 Forging the local SQLite database with {len(batch_data)} unique terms...")
    
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

    # Commit to SQLite in efficient chunks
    chunk_size = 5000
    total_inserted = 0
    
    if batch_data:
        for i in range(0, len(batch_data), chunk_size):
            chunk = batch_data[i:i + chunk_size]
            cursor.executemany("INSERT OR IGNORE INTO entries (word, localized_text) VALUES (?, ?)", chunk)
            total_inserted += cursor.rowcount
            
    conn.commit()
    conn.close()
    
    print("\n" + "="*50)
    print("✅ SUCCESS! The combined master database is complete.")
    print(f"📍 Location: {os.path.abspath(db_name)}")
    print(f"📊 Total unique vocabulary terms saved: {total_inserted}")
    print("="*50)

if __name__ == "__main__":
    build_combined_db()