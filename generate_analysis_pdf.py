import markdown2
from fpdf import FPDF

with open("Hospimed_Comprehensive_Analysis.md", "r", encoding="utf-8") as f:
    md_text = f.read()

html = markdown2.markdown(md_text)

class PDF(FPDF):
    pass

pdf = PDF()
pdf.add_page()
pdf.set_font("helvetica", size=12)
pdf.write_html(html)

pdf.output("Hospimed_Comprehensive_Analysis.pdf")
