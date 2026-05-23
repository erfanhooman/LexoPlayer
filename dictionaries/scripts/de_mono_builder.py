import sqlite3
import json
import os
import urllib.request
from tqdm import tqdm

def build_german_monolingual_db():
    print("🚀 Starting German Monolingual Database Build...")
    db_name = "german_monolingual.db"
    
    if os.path.exists(db_name):
        os.remove(db_name)
        
    conn = sqlite3.connect(db_name)
    cursor = conn.cursor()
    cursor.execute("""
    CREATE TABLE entries (
        word TEXT PRIMARY KEY,
        html_definition TEXT
    );
    """)
    cursor.execute("CREATE INDEX idx_entries_word ON entries(word);")
    
    # 1.6 Million Word German library
    url = "https://raw.githubusercontent.com/Jonny-exe/German-Words-Library/master/German-words-1600000-words.json"
    
    try:
        print("📥 Fetching massive German word list...")
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req) as response:
            word_list = json.loads(response.read().decode('utf-8'))
            
        batch_data = []
        for word in tqdm(word_list, desc="Processing German Words"):
            if word and isinstance(word, str):
                clean_word = word.strip()
                # Create standard structured view matching your schema
                formatted_entry = {
                    "part_of_speech": "N/A",
                    "definitions": [{"meaning": "Deutsches Wort", "example": ""}]
                }
                json_blob = json.dumps(formatted_entry, ensure_ascii=False)
                batch_data.append((clean_word.lower(), json_blob))
                
        print("💾 Writing rows to SQLite...")
        cursor.executemany("INSERT OR IGNORE INTO entries (word, html_definition) VALUES (?, ?)", batch_data)
        conn.commit()
        print(f"✅ Success! Saved {len(batch_data)} words to {db_name}")
        
    except Exception as e:
        print(f"❌ Error: {e}")
    finally:
        conn.close()

if __name__ == "__main__":
    build_german_monolingual_db()
