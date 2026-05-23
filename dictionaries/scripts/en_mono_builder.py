import sqlite3
import json
import os
import urllib.request
import string
from tqdm import tqdm # Standard library for progress bars

def build_full_monolingual_db():
    print("🚀 Starting LexoPlayer Full Database Build (New Schema)...")
    db_name = "english_monolingual.db"
    
    # Start fresh by removing any existing DB
    if os.path.exists(db_name):
        os.remove(db_name)
        
    conn = sqlite3.connect(db_name)
    cursor = conn.cursor()
    
    # Set up the schema exactly as defined in your updated README
    cursor.execute("""
    CREATE TABLE entries (
        word TEXT PRIMARY KEY,
        html_definition TEXT
    );
    """)
    cursor.execute("CREATE INDEX idx_entries_word ON entries(word);")
    
    # Wordset data is split by alphabet + misc file
    files_to_download = list(string.ascii_lowercase) + ['misc']
    total_inserted = 0
    
    # Initialize the Progress Bar
    pbar = tqdm(files_to_download, desc="Downloading & Processing", unit="file")
    
    for file_prefix in pbar:
        url = f"https://raw.githubusercontent.com/wordset/wordset-dictionary/master/data/{file_prefix}.json"
        pbar.set_description(f"Processing '{file_prefix}.json'")
        
        try:
            # Fetch the raw JSON from GitHub
            with urllib.request.urlopen(url) as response:
                wordset_data = json.loads(response.read().decode('utf-8'))
            
            # Prepare data for batch insertion (faster than single inserts)
            batch_data = []
            
            for word_key, data in wordset_data.items():
                meanings_list = data.get("meanings", [])
                if not meanings_list:
                    continue
                
                primary_pos = meanings_list[0].get("speech_part", "unknown")
                
                # ---------------------------------------------------------
                # UPDATED SCHEMA: Only part_of_speech and definitions
                # ---------------------------------------------------------
                formatted_entry = {
                    "part_of_speech": primary_pos,
                    "definitions": [
                        {"meaning": m.get("def", ""), "example": m.get("example", "")} 
                        for m in meanings_list
                    ]
                }
                
                json_blob = json.dumps(formatted_entry, ensure_ascii=False)
                batch_data.append((word_key.lower().strip(), json_blob))
            
            # Batch insert to improve performance
            cursor.executemany("INSERT OR IGNORE INTO entries (word, html_definition) VALUES (?, ?)", batch_data)
            total_inserted += len(batch_data)
            
        except Exception as e:
            tqdm.write(f"⚠️ Warning: Could not process {file_prefix}: {e}")

    # Commit and finalize the file
    conn.commit()
    conn.close()
    
    print("\n" + "="*40)
    print(f"✅ Success! Database generated with the new schema.")
    print(f"📍 Location: {os.path.abspath(db_name)}")
    print(f"📊 Total words: {total_inserted}")
    print("="*40)

if __name__ == "__main__":
    build_full_monolingual_db()
