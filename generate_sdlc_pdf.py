import markdown2
from fpdf import FPDF

with open("SDLC_Document.md", "r", encoding="utf-8") as f:
    md_text = f.read()

html = markdown2.markdown(md_text)

class PDF(FPDF):
    pass

pdf = PDF()
pdf.add_page()
pdf.set_font("helvetica", size=12)
pdf.write_html(html)

pdf.output("SDLC_Document.pdf")
