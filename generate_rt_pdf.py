import markdown2
from fpdf import FPDF

with open("Rahul_Traders_Documentation.md", "r", encoding="utf-8") as f:
    md_text = f.read()

html = markdown2.markdown(md_text)

class PDF(FPDF):
    pass

pdf = PDF()
pdf.add_page()
pdf.set_font("helvetica", size=12)
pdf.write_html(html)

pdf.output("Rahul_Traders_Documentation.pdf")
