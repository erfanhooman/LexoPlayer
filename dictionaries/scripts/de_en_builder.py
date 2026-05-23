import sqlite3
import json
import os
import urllib.request
from tqdm import tqdm

def build_de_en_db():
    print("🚀 Starting German-to-English Dictionary Build...")
    db_name = "german_to_english_bilangual.db"
    
    if os.path.exists(db_name):
        os.remove(db_name)
        
    conn = sqlite3.connect(db_name)
    cursor = conn.cursor()
    cursor.execute("""
    CREATE TABLE entries (
        word TEXT PRIMARY KEY,
        localized_text TEXT
    );
    """)
    cursor.execute("CREATE INDEX idx_entries_word ON entries(word);")
    
    # German-English Map endpoint
    url = "https://raw.githubusercontent.com/hathibelagal/German-English-JSON-Dictionary/master/german_english.json"
    
    try:
        print("📥 Fetching translation mappings...")
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req) as response:
            dict_data = json.loads(response.read().decode('utf-8'))
            
        batch_data = []
        for de_word, en_meaning in tqdm(dict_data.items(), desc="Formatting pairs"):
            if de_word and en_meaning:
                batch_data.append((de_word.lower().strip(), en_meaning.strip()))
                
        print("💾 Writing rows to SQLite...")
        cursor.executemany("INSERT OR IGNORE INTO entries (word, localized_text) VALUES (?, ?)", batch_data)
        conn.commit()
        print(f"✅ Success! Saved {len(batch_data)} mappings to {db_name}")
        
    except Exception as e:
        print(f"❌ Error: {e}")
    finally:
        conn.close()

if __name__ == "__main__":
    build_de_en_db()
