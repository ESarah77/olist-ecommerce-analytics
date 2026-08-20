"""Download the Olist Brazilian E-Commerce dataset from Kaggle into data/raw/."""

from pathlib import Path
import subprocess

DATA_DIR = Path("data/raw")

if any(DATA_DIR.glob("*.csv")):
    print(f"Data already present in {DATA_DIR}, skipping download.")
else:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            "kaggle", "datasets", "download",
            "-d", "olistbr/brazilian-ecommerce",
            "-p", str(DATA_DIR),
            "--unzip",
        ],
        check=True,
    )
    print(f"Dataset downloaded and extracted to {DATA_DIR}.")
