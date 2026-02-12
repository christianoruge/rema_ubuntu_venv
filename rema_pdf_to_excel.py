# -*- coding: utf-8 -*-

import pandas as pd
from openpyxl.utils import get_column_letter
import re
import os
import tempfile
from typing import List, Dict, Tuple, Optional, Iterable, Set
from pathlib import Path
from pypdf import PdfReader
import sys
import threading
import time

# Detect environment
IS_CONTAINER = os.getenv('CONTAINER_ENV', 'false').lower() == 'true'

# Import tkinter only if NOT running as container app
if not IS_CONTAINER:
    import tkinter as tk
    from tkinter import filedialog

# Import Flask only if running as container app
if IS_CONTAINER:
    from flask import Flask, request, jsonify, send_file
    app = Flask(__name__)


def select_pdf_file():
    """Select a PDF file using file dialog and return the file path."""
    if IS_CONTAINER:
        return None  # Not applicable for container
    
    
    
    root = tk.Tk()
    root.withdraw()  # Hide the root window
    pdf_path = filedialog.askopenfilename(
        title="Velg PDF-fil",
        filetypes=[("PDF files", "*.pdf"), ("All files", "*.*")]
    )
    return pdf_path, root  # Return path and root for proper cleanup


def select_output_folder(root):
    """Select an output folder using file dialog and return the folder path."""
    if IS_CONTAINER:
        return str(Path(tempfile.gettempdir()) / "output")  # Default container output folder
    
    from tkinter import filedialog
    
    folder_path = filedialog.askdirectory(
        title="Velg mappe for å lagre Excel-filen"  
    )
    root.destroy()
    return folder_path


if not IS_CONTAINER:
    result = select_pdf_file()
    if result:
        pdf, root = result
        output_folder = select_output_folder(root)
    else:
        pdf = None
        output_folder = None
else:
    pdf = None
    output_folder = str(Path(tempfile.gettempdir()) / "output")


# ---------- Konfigurasjon ----------
OUTPUT_SUFFIX = "_konvertert.xlsx"  # filnavn-suffix for generert Excel
SHEET_NAME = "Fakturadetaljer"
TABLE_COLUMNS = [
    "Dato",
    "Kvitteringsnr",
    "Ansvarlig",
    "EAN",
    "Varetekst",
    "Antall",
    "Nettopris",
    "Mva",
    "Beløp i NOK",
    "Sum 25%", # Ny kolonne
    "Sum 15%",  # Ny kolonne
    "Sum 0%" # Added new column header
]

# Regex for rekvisisjonsseksjonen (dato, kvnr, ansvarlig, grunnlag, mva, total)
RE_REQUISITION_ROW = re.compile(
    r"^(?P<dato>\d{2}\.\d{2}\.\d{4})\s+kvitteringsnr:\s+(?P<kvnr>\d+)\s+(?P<ansvarlig>.+?)\s+(?P<grunnlag>\d+(?:[,.]\d*)?)\s+(?P<mva>\d+(?:[,.]\d*)?)\s+(?P<total>\d+(?:[,.]\d*)?)$",
    re.IGNORECASE,
)

# Summeringslinje per kvittering
RE_SUM_LINE = re.compile(
    r"^(?P<dato>\d{2}\.\d{2}\.\d{4})\s+Sum\s+kvitteringsnr:\s+(?P<kvnr>\d+)\s+(?P<grunnlag>\d+(?:[,.]\d*)?)\s+(?P<total>\d+(?:[,.]\d*)?)$",
    re.IGNORECASE,
)

# Produktlinjer - Modified RE_PRODUCT to accept single-digit EANs
RE_PRODUCT = re.compile(
    r"^(?P<ean>\d+)\s+(?P<varetekst>.+?)\s+(?P<antall>\d+(?:[,.]\d*)?)\s+(?P<netto>\d+(?:[,.]\d*)?)\s+(?P<mva>\d+%?)\s+(?P<belop>\d+(?:[,.]\d*)?)$"
)

def normalize_ws(text: str) -> str:
    """Normaliser whitespace (non-breaking space og tab til vanlig mellomrom)."""
    return re.sub(r"[\u00A0\t]", " ", text or "")

def extract_lines(pdf_path: Path) -> List[str]:
    """Les PDF og returner liste av (trimmede) linjer."""
    with pdf_path.open("rb") as f:
        reader = PdfReader(f)
        lines: List[str] = []
        for p in reader.pages:
            txt = normalize_ws(p.extract_text())
            lines.extend([ln.strip() for ln in txt.split("\n") if ln.strip()])
    return lines

def build_ansvarlig_map(lines: List[str]) -> Dict[Tuple[str, str], str]:
    """Bygg mapping (Dato, Kvitteringsnr) -> Ansvarlig fra rekvisisjonsseksjonen."""
    ansvarlig_map: Dict[Tuple[str, str], str] = {}
    for line in lines:
        m = RE_REQUISITION_ROW.match(line)
        if m:
            dato = m.group("dato")
            kvnr = m.group("kvnr")
            ansvarlig = m.group("ansvarlig").strip()
            ansvarlig_map[(dato, kvnr)] = ansvarlig
    return ansvarlig_map

def parse_pdf_to_rows(lines: List[str]) -> List[List[str]]:
    """Parse PDF-linjer til tabellrader inkl. summeringslinjer og tom rad etter hver sum."""
    ansvarlig_map = build_ansvarlig_map(lines)
    rows: List[List[str]] = []
    current_products: List[Dict[str, str]] = []
    sum_25_percent = 0.0
    sum_15_percent = 0.0
    sum_0_percent = 0.0 # Initialize new sum variable

    for line in lines:
        # print(f"Processing line: {line}") # Debugging print
        m_prod = RE_PRODUCT.match(line)
        m_sum = RE_SUM_LINE.match(line)

        if m_prod:
            # print(f"RE_PRODUCT matched: Mva={m_prod.group('mva')}, Belop={m_prod.group('belop')}, EAN={m_prod.group('ean')}") # Debugging print with EAN
            belop = float(m_prod.group("belop").replace(",", "."))
            mva_str = m_prod.group("mva")

            # Normalize mva_str to always include '%' for consistency in comparison
            if mva_str == "0":
                mva_str = "0%"

            if mva_str == "25%":
                sum_25_percent += belop
            elif mva_str == "15%":
                sum_15_percent += belop
            elif mva_str == "0%": # Handle 0% MVA
                sum_0_percent += belop

            current_products.append({
                "ean": m_prod.group("ean"),
                "varetekst": m_prod.group("varetekst").strip(),
                "antall": m_prod.group("antall"),
                "netto": m_prod.group("netto"),
                "mva": mva_str, # Use normalized mva_str
                "belop": m_prod.group("belop"),
            })
            continue
        # elif not m_sum: # Debugging print for non-matching lines, but not sum line
            # print(f"RE_PRODUCT and RE_SUM_LINE failed to match line: {line}") # Changed condition to check for both for clarity

        if m_sum:
            dato = m_sum.group("dato")
            kvnr = m_sum.group("kvnr")
            grunnlag = m_sum.group("grunnlag").replace(",", ".")
            total = m_sum.group("total").replace(",", ".")
            ansvarlig = ansvarlig_map.get((dato, kvnr), "")

            for prod in current_products:
                rows.append([
                    dato,
                    kvnr,
                    ansvarlig,
                    prod["ean"],
                    prod["varetekst"],
                    prod["antall"].replace(",", "."),
                    prod["netto"].replace(",", "."),
                    prod["mva"],
                    prod["belop"].replace(",", "."),
                    "", # Sum 25% (empty for product line)
                    "",  # Sum 15% (empty for product line)
                    ""  # Sum 0% (empty for product line)
                ])

            # Summeringsrad
            rows.append([
                dato,
                kvnr,
                ansvarlig,
                "",                                 # EAN
                f"Sum kvitteringsnr {kvnr}",         # Varetekst
                "",                                  # Antall
                grunnlag,                            # Nettopris (bruker grunnlag som "netto")
                "",                                  # Mva (sumlinjen har ikke %)
                total,                               # Beløp i NOK (total)
                str(round(sum_25_percent, 2)).replace('.', ','), # Sum 25%
                str(round(sum_15_percent, 2)).replace('.', ','),  # Sum 15%
                str(round(sum_0_percent, 2)).replace('.', ',') # Sum 0%
            ])

            # Tom rad etter hver sumlinje
            rows.append(["", "", "", "", "", "", "", "", "", "", "", ""])

            current_products = []
            sum_25_percent = 0.0 # Reset for next receipt
            sum_15_percent = 0.0 # Reset for next receipt
            sum_0_percent = 0.0 # Reset for next receipt
            continue

    # Edge case: produkter uten sumlinje
    if current_products:
        for prod in current_products:
            rows.append([
                "", "", "",  # Dato, Kvnr, Ansvarlig ukjent
                prod["ean"], prod["varetekst"], prod["antall"].replace(",", "."),
                prod["netto"].replace(",", "."), prod["mva"], prod["belop"].replace(",", "."),
                "", # Sum 25% (empty for product line)
                "",  # Sum 15% (empty for product line)
                ""  # Sum 0% (empty for product line)
            ])

    return rows

def write_excel(rows: List[List[str]], out_path: Path) -> None:
    """Skriv resultat til Excel i XLSX_DIR."""
    try:
        # Ensure the parent directory exists
        out_path.parent.mkdir(parents=True, exist_ok=True)
        
        # Check write permissions
        if not os.access(str(out_path.parent), os.W_OK):
            raise PermissionError(f"No write permission for directory: {out_path.parent}")
        
        # If file already exists, try to remove it (it might be locked)
        if out_path.exists():
            try:
                out_path.unlink()
            except PermissionError:
                # If we can't remove it, generate a unique filename
                counter = 1
                stem = out_path.stem
                suffix = out_path.suffix
                while True:
                    new_path = out_path.parent / f"{stem}_{counter}{suffix}"
                    if not new_path.exists():
                        out_path = new_path
                        print(f"[INFO] Original file is locked. Using: {out_path}")
                        break
                    counter += 1
        
        df = pd.DataFrame(rows, columns=TABLE_COLUMNS)

        # Numeriske kolonner til float
        for col in ["Antall", "Nettopris", "Beløp i NOK", "Sum 25%", "Sum 15%", "Sum 0%"]:
            # Convert comma to dot for decimal conversion, then to numeric
            df[col] = df[col].astype(str).str.replace(',', '.', regex=False)
            df[col] = pd.to_numeric(df[col], errors="coerce")

        # Calculate grand totals
        total_belop = df["Beløp i NOK"].sum()
        total_sum_25 = df["Sum 25%"].sum()
        total_sum_15 = df["Sum 15%"].sum()
        total_sum_0 = df["Sum 0%"].sum()

        # Create a new row for the grand totals
        total_row = {
            "Dato": "",
            "Kvitteringsnr": "",
            "Ansvarlig": "",
            "EAN": "",
            "Varetekst": "Total",
            "Antall": "",
            "Nettopris": "",
            "Mva": "",
            "Beløp i NOK": total_belop,
            "Sum 25%": total_sum_25,
            "Sum 15%": total_sum_15,
            "Sum 0%": total_sum_0
        }

        # Append the total row to the DataFrame
        df = pd.concat([df, pd.DataFrame([total_row])], ignore_index=True)

        # Write to Excel in the desired folder
        with pd.ExcelWriter(str(out_path), engine="openpyxl") as writer:
            df.to_excel(writer, index=False, sheet_name=SHEET_NAME)

            # Auto-adjust column widths
            workbook = writer.book
            worksheet = writer.sheets[SHEET_NAME]

            for i, col in enumerate(df.columns):
                max_len = 0
                # Check header length
                max_len = max(max_len, len(str(col)))
                # Check column content length
                for val in df[col]:
                    try:
                        max_len = max(max_len, len(str(val)))
                    except TypeError:
                        max_len = max(max_len, len(str(val))) # Convert to string for length calculation

                adjusted_width = (max_len + 2) # Add a little padding
                worksheet.column_dimensions[get_column_letter(i + 1)].width = adjusted_width

        print(f"[OK] Skrev {len(df)} rader (inkl. summeringer og tomme rader) til: {out_path}")
    except Exception as e:
        print(f"[ERROR] Feil ved skriving av Excel-fil: {e}")
        raise

def process_file(pdf_name: str) -> Path:
    """Prosesser en PDF-fil og returner stien til den genererte Excel-filen."""
    # Use the globally defined XLSX_DIR (defined in the main execution block)
    pdf_path = Path(pdf_name)

    # Ensure XLSX_DIR exists
    XLSX_DIR.mkdir(exist_ok=True)

    # Output fil i ./XLSX
    out_path = XLSX_DIR / (pdf_path.stem + OUTPUT_SUFFIX)

    lines = extract_lines(pdf_path)
    rows = parse_pdf_to_rows(lines)
    write_excel(rows, out_path)
    return out_path  # Return the path to the generated Excel file


# ========== FLASK API FOR CONTAINER APP ==========
if IS_CONTAINER:
    def shutdown_container():
        """Shutdown the Flask server to stop incurring Azure costs."""
        print("[INFO] Excel file downloaded successfully. Shutting down container...")
        # Give the response time to send before exiting
        time.sleep(1)
        os._exit(0)
    
    @app.route('/health', methods=['GET'])
    def health():
        """Health check endpoint."""
        return jsonify({"status": "healthy"}), 200

    @app.route('/convert', methods=['POST'])
    def convert_pdf():
        """
        API endpoint to convert PDF to Excel.
        Expects a multipart form with 'file' field containing the PDF.
        Returns the Excel file or an error message.
        """
        try:
            if 'file' not in request.files:
                return jsonify({"error": "No file provided"}), 400
            
            file = request.files['file']
            if file.filename == '':
                return jsonify({"error": "No file selected"}), 400
            
            if not file.filename.lower().endswith('.pdf'):
                return jsonify({"error": "File must be a PDF"}), 400
            
            # Create temp directory if it doesn't exist
            temp_base = Path(tempfile.gettempdir())
            temp_dir = temp_base / "pdf_input"
            temp_dir.mkdir(exist_ok=True, parents=True)
            
            # Save uploaded PDF
            pdf_path = temp_dir / file.filename
            file.save(str(pdf_path))
            
            # Process the PDF
            output_dir = temp_base / "output"
            output_dir.mkdir(exist_ok=True, parents=True)
            global XLSX_DIR
            XLSX_DIR = output_dir
            
            excel_path = process_file(str(pdf_path))
            
            # Schedule container shutdown after response is sent
            shutdown_thread = threading.Thread(target=shutdown_container, daemon=True)
            shutdown_thread.start()
            
            # Return the Excel file
            return send_file(
                str(excel_path),
                as_attachment=True,
                download_name=Path(excel_path).name,
                mimetype='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
            )
        
        except Exception as e:
            return jsonify({"error": str(e)}), 500
        
        finally:
            # Cleanup temp files
            try:
                if pdf_path and pdf_path.exists():
                    pdf_path.unlink()
            except:
                pass


# ========== LOCAL EXECUTION (VS CODE) ==========
if not IS_CONTAINER:
    if pdf and Path(pdf).exists():  # Check if pdf file path exists
        if not output_folder:  # If user cancelled folder selection
            print("No output folder selected. Using default folder './XLSX'")
            output_folder = "./XLSX"
        
        pdf_filename = pdf

        # Define the directory for Excel output
        XLSX_DIR = Path(output_folder)

        # Process the PDF and get the output Excel file path
        try:
            final_excel_path = process_file(pdf_filename)
            print(f"Excel file created: {final_excel_path}")
        except Exception as e:
            print(f"Error processing PDF: {e}")
            if not IS_CONTAINER:
                import tkinter as tk
                from tkinter import messagebox
                
                root = tk.Tk()
                root.withdraw()
                messagebox.showerror("Feil", f"Feil under behandling av PDF:\n{e}")
                root.destroy()
            sys.exit(1)
        
        # Show success popup (only in local mode)
        if not IS_CONTAINER:
            import tkinter as tk
            from tkinter import messagebox
            
            root = tk.Tk()
            root.withdraw()
            messagebox.showinfo("Ferdig", "Filen er lagret på valgt plassering.")
            root.destroy()
    else:
        print("No PDF file selected or file not found.")

else:
    # ========== START FLASK SERVER FOR CONTAINER ==========
    port = int(os.getenv('PORT', 8000))
    app.run(host='0.0.0.0', port=port, debug=False)

print("Updated TABLE_COLUMNS list:", TABLE_COLUMNS)

