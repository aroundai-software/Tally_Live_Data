from fpdf import FPDF
from fpdf.drawing import DeviceRGB

# ─────────────────────────────────────────────
#  Color Palette (R, G, B tuples)
# ─────────────────────────────────────────────
NAVY       = (13,  71, 161)
BLUE       = (26, 115, 232)
TEAL       = (0,  150, 136)
AMBER      = (245, 127, 23)
RED        = (198,  55,  45)
GREEN      = (67,  160,  71)
PURPLE     = (123,  31, 162)
LIGHT_GREY = (245, 247, 251)
MID_GREY   = (200, 210, 225)
DARK_TEXT  = (15,  26,  43)
MID_TEXT   = (90, 110, 140)
WHITE      = (255, 255, 255)
BLACK      = (0,   0,   0)


class OrderXLitePDF(FPDF):
    """Professional OrderX-Lite product brochure -- Times New Roman throughout."""

    # ─── primitive helpers ────────────────────────────────────────────────────

    def _rgb(self, col):
        return col[0], col[1], col[2]

    def fill_rect(self, x, y, w, h, col):
        self.set_fill_color(*col)
        self.rect(x, y, w, h, style='F')

    def h_line(self, x, y, w, col=MID_GREY, lw=0.3):
        self.set_draw_color(*col)
        self.set_line_width(lw)
        self.line(x, y, x + w, y)

    def circle(self, cx, cy, r, col):
        self.set_fill_color(*col)
        self.ellipse(cx - r, cy - r, r * 2, r * 2, style='F')

    def t(self, size, bold=False, italic=False):
        style = ('B' if bold else '') + ('I' if italic else '')
        self.set_font('Times', style, size)

    def pill(self, x, y, label, bg, fg):
        """Small coloured pill label."""
        self.t(7.5, bold=True)
        w = self.get_string_width(label) + 8
        self.fill_rect(x, y, w, 6, bg)
        self.set_text_color(*fg)
        self.set_xy(x + 4, y + 0.7)
        self.cell(w - 8, 5.3, label)

    def icon_box(self, x, y, size, bg, label):
        """Small square icon with 2-letter code."""
        self.fill_rect(x, y, size, size, bg)
        self.t(size * 0.46, bold=True)
        self.set_text_color(*WHITE)
        sw = self.get_string_width(label)
        self.set_xy(x + (size - sw) / 2 - 0.5, y + size * 0.20)
        self.cell(sw + 1, size * 0.6, label, align='C')

    # ─── header / footer ─────────────────────────────────────────────────────

    def header(self):
        pass

    def footer(self):
        if self.page_no() == 1:
            return
        self.set_y(-12)
        self.h_line(14, self.get_y(), 182)
        self.set_y(-10)
        self.t(8)
        self.set_text_color(*MID_TEXT)
        self.cell(0, 5, f'OrderX-Lite  |  Tally-Connected Business Intelligence  |  Page {self.page_no()}',
                  align='C')

    # ═════════════════════════════════════════════════════════════════════════
    #  PAGE 1 -- COVER
    # ═════════════════════════════════════════════════════════════════════════
    def page_cover(self):
        self.add_page()

        # Hero gradient (two-tone band)
        self.fill_rect(0, 0, 210, 125, NAVY)
        self.fill_rect(0, 100, 210, 35, BLUE)

        # Decorative accent circles
        self.circle(178, 18, 28, (26, 90, 190))
        self.circle(8,  112, 20, (13, 60, 140))
        self.circle(155, 92, 10, AMBER)

        # Tag
        self.pill(14, 20, '  TALLY-CONNECTED BUSINESS APP  ', BLUE, WHITE)

        # Product title
        self.set_xy(14, 32)
        self.t(40, bold=True)
        self.set_text_color(*WHITE)
        self.cell(0, 17, 'OrderX-Lite')

        # Sub-headline
        self.set_xy(14, 52)
        self.t(13, italic=True)
        self.set_text_color(200, 220, 255)
        self.multi_cell(145, 6.5, 'Live business data on your phone.\nFrom Tally. For every business.')

        # Description
        self.set_xy(14, 70)
        self.t(10)
        self.set_text_color(175, 200, 245)
        self.multi_cell(152, 5.2,
            'OrderX-Lite connects seamlessly to your Tally data and puts it right '
            'in your pocket -- your stock, invoices, customers, outstanding bills, '
            'daily accounts, and deep analytics -- available anytime, anywhere.')

        # Feature pills
        tags = ['Live Stock', 'Sales & Purchases', 'Receivables', 'Daybook', 'Analytics']
        tx, ty = 14, 95
        for tag in tags:
            self.t(7.5, bold=True)
            tw = self.get_string_width(tag) + 9
            self.fill_rect(tx, ty, tw, 7, WHITE)
            self.set_text_color(*NAVY)
            self.set_xy(tx + 2, ty + 0.8)
            self.cell(tw - 4, 6, tag)
            tx += tw + 4

        # White body
        self.fill_rect(0, 113, 210, 185, WHITE)

        # "Works for any business" band
        self.fill_rect(0, 113, 210, 16, LIGHT_GREY)
        self.set_xy(14, 117)
        self.t(9, bold=True)
        self.set_text_color(*MID_TEXT)
        self.cell(0, 6, 'Works for any business  --  Retail, Wholesale, Distribution, Manufacturing, Services & more')
        self.h_line(14, 129, 182, lw=0.4)

        # "What is OrderX-Lite?" section
        self.set_xy(14, 133)
        self.t(17, bold=True)
        self.set_text_color(*DARK_TEXT)
        self.cell(0, 9, 'What is OrderX-Lite?')

        self.set_xy(14, 145)
        self.t(10.5)
        self.set_text_color(*DARK_TEXT)
        self.multi_cell(182, 5.8,
            'Most businesses using Tally face a silent productivity gap. The moment your team '
            'steps away from the office desktop, they lose visibility. Salespeople do not know '
            'live stock levels. Owners cannot check outstanding dues. Managers have no idea how '
            'the day is going financially. Phone calls back to office waste hours every day.\n\n'
            'OrderX-Lite bridges this gap -- without replacing Tally or changing how your team '
            'works. It reads your Tally data in real-time through a secure cloud sync and '
            'presents it in a clean smartphone interface. No duplicate entry. No separate '
            'software. Just your Tally data, always in your pocket.')

        # 4 KPI highlight boxes
        kpis = [
            ('Stock',    'Live inventory\nvaluation & counts',    BLUE),
            ('Bills',    'Outstanding\nreceivables & payables',   TEAL),
            ('Profit',   'Daily revenue vs.\nestimated profit',    GREEN),
            ('Any Biz',  'Works for retail,\nwholesale & more',   AMBER),
        ]
        bx, bw = 14, 43
        for title, desc, col in kpis:
            self.fill_rect(bx, 212, bw, 30, LIGHT_GREY)
            self.fill_rect(bx, 212, bw, 5, col)
            self.t(11, bold=True)
            self.set_text_color(*DARK_TEXT)
            self.set_xy(bx + 2, 219)
            self.cell(bw - 4, 6, title, align='C')
            self.t(8)
            self.set_text_color(*MID_TEXT)
            self.set_xy(bx + 2, 226)
            self.multi_cell(bw - 4, 4, desc, align='C')
            bx += bw + 3

        # Bottom credits
        self.set_xy(14, 248)
        self.t(8.5, italic=True)
        self.set_text_color(*MID_TEXT)
        self.cell(0, 5, 'Built on Flutter  *  Powered by Supabase PostgreSQL  *  Syncs with Tally  *  Android, iOS & Web')
        self.set_xy(14, 255)
        self.t(8.5, italic=True)
        self.cell(0, 5, 'AroundAI Software  |  contact@aroundai.in')

    # ═════════════════════════════════════════════════════════════════════════
    #  PAGE 2 -- PROBLEM + HOW IT WORKS
    # ═════════════════════════════════════════════════════════════════════════
    def page_problem(self):
        self.add_page()

        # ─ Problem ───────────────────────────────────────────────────────────
        self.pill(14, 14, '  THE PROBLEM  ', NAVY, WHITE)

        self.set_xy(14, 25)
        self.t(19, bold=True)
        self.set_text_color(*DARK_TEXT)
        self.cell(0, 9, 'Your business data is trapped on a desktop.')

        self.set_xy(14, 36)
        self.t(10, italic=True)
        self.set_text_color(*MID_TEXT)
        self.cell(0, 6, 'Most Tally-based businesses still operate like this:')

        problems = [
            ('Blind Sales Team',
             'Salespeople visit customers without knowing live stock levels, '
             'pending dues, or credit limits. Orders are taken on gut feel.'),
            ('Delayed Invoices',
             'Invoices are raised on the desktop hours after the sale, reaching '
             'customers the next day -- creating disputes and payment delays.'),
            ('No Owner Visibility',
             'Owners cannot see daily cash inflow/outflow, receivables, or sales '
             'performance without sitting at the office computer.'),
            ('Capital Tied in Dead Stock',
             'Thousands of rupees sit in inventory that has not sold in months. '
             'Nobody tracks it because the data takes too long to compile.'),
            ('Dormant Customers Slip Away',
             'Valuable old customers stop buying and nobody notices. There is no '
             'proactive system to flag or re-engage them.'),
        ]

        py = 46
        for i, (title, desc) in enumerate(problems):
            self.circle(20, py + 4, 4, RED)
            self.t(8.5, bold=True)
            self.set_text_color(*WHITE)
            self.set_xy(17, py + 1.2)
            self.cell(7, 5.5, str(i + 1), align='C')

            self.t(11, bold=True)
            self.set_text_color(*DARK_TEXT)
            self.set_xy(30, py)
            self.cell(0, 5.5, title)

            self.t(9.5)
            self.set_text_color(*MID_TEXT)
            self.set_xy(30, py + 5.5)
            self.multi_cell(166, 4.8, desc)
            py += 23

        # ─ Divider ───────────────────────────────────────────────────────────
        self.h_line(14, py + 3, 182, lw=0.5)
        py += 11

        # ─ How it Works ──────────────────────────────────────────────────────
        self.pill(14, py, '  HOW IT WORKS  ', TEAL, WHITE)
        py += 11

        self.set_xy(14, py)
        self.t(19, bold=True)
        self.set_text_color(*DARK_TEXT)
        self.cell(0, 9, 'Three steps. Zero disruption.')
        py += 11

        self.set_xy(14, py)
        self.t(10, italic=True)
        self.set_text_color(*MID_TEXT)
        self.cell(0, 6, 'OrderX-Lite works alongside your existing Tally setup -- nothing changes for your accountants.')
        py += 10

        steps = [
            (NAVY,  '1', 'Connect Your Tally',
             'A background connector syncs your Tally data -- items, '
             'customers, pricing, invoices, outstanding, and daybook -- '
             'securely to the cloud. Automatic, no manual effort needed.'),
            (BLUE,  '2', 'Team Opens the App',
             'Each team member opens OrderX-Lite on their smartphone. '
             'Every person sees only their authorized data. Live, '
             'searchable, and always up-to-date. No shared logins.'),
            (GREEN, '3', 'Act on Real-Time Data',
             'Salespeople check stock instantly. Owners view profit '
             'trends. Managers review outstanding bills. Accountants '
             'verify daybook -- all from their phone, anywhere, anytime.'),
        ]

        sw = 57
        for col, num, title, desc in steps:
            self.fill_rect(14, py, sw, 58, LIGHT_GREY)
            self.fill_rect(14, py, sw, 6, col)

            self.circle(22, py + 15, 5.5, col)
            self.t(10, bold=True)
            self.set_text_color(*WHITE)
            self.set_xy(18.5, py + 11)
            self.cell(9, 8, num, align='C')

            self.t(10.5, bold=True)
            self.set_text_color(*DARK_TEXT)
            self.set_xy(15, py + 23)
            self.cell(sw - 3, 6, title)

            self.t(8.5)
            self.set_text_color(*MID_TEXT)
            self.set_xy(15, py + 30)
            self.multi_cell(sw - 5, 4.4, desc)

            # shift x -- but we need 3 side-by-side
            if num == '1':
                self.set_xy(14 + sw + 4, py)
            elif num == '2':
                self.set_xy(14 + (sw + 4) * 2, py)

            # Actually: draw each with correct x
        # Redo steps with correct x positions
        self.fill_rect(0, py, 210, 0, WHITE)  # reset -- redraw above
        sx_list = [14, 14 + sw + 4, 14 + (sw + 4) * 2]
        for idx, (col, num, title, desc) in enumerate(steps):
            sx = sx_list[idx]
            self.fill_rect(sx, py, sw, 58, LIGHT_GREY)
            self.fill_rect(sx, py, sw, 6, col)

            self.circle(sx + 8, py + 15, 5.5, col)
            self.t(10, bold=True)
            self.set_text_color(*WHITE)
            self.set_xy(sx + 4.5, py + 11)
            self.cell(9, 8, num, align='C')

            self.t(10.5, bold=True)
            self.set_text_color(*DARK_TEXT)
            self.set_xy(sx + 3, py + 23)
            self.cell(sw - 5, 6, title)

            self.t(8.5)
            self.set_text_color(*MID_TEXT)
            self.set_xy(sx + 3, py + 30)
            self.multi_cell(sw - 5, 4.4, desc)

    # ═════════════════════════════════════════════════════════════════════════
    #  PAGE 3 -- 8 CORE MODULES
    # ═════════════════════════════════════════════════════════════════════════
    def page_modules(self):
        self.add_page()

        self.pill(14, 14, '  CORE MODULES  ', NAVY, WHITE)

        self.set_xy(14, 25)
        self.t(19, bold=True)
        self.set_text_color(*DARK_TEXT)
        self.cell(0, 9, 'Eight powerful modules. One app.')

        self.set_xy(14, 36)
        self.t(10, italic=True)
        self.set_text_color(*MID_TEXT)
        self.multi_cell(182, 5.5,
            'Every module solves a real business problem. Together they give you '
            'a complete 360-degree view of your operations -- from any device.')

        modules = [
            (NAVY,   'DB', 'Dashboard & KPI Overview',
             'Instant snapshot: Total Stock Value, Total Sales, Total Purchases, '
             'Net Receivables, Net Payables, and today\'s cash Inflow & Outflow. '
             'A colour-coded Net Balance card instantly shows whether the business '
             'is net receivable or payable. Tap any KPI to drill into full detail.'),
            (TEAL,   'ST', 'Stock & Inventory',
             'Complete product catalog synced from Tally -- Item Name, Quantity, '
             'Rate, Standard Cost, MRP. Smart multi-column search by name and '
             'part number. Per-item inventory valuation (Qty x Rate) calculated '
             'automatically. No more calling the warehouse before promising stock.'),
            (BLUE,   'LD', 'Ledgers & Customer Directory',
             'Full customer list with name, city, mobile number, credit limit, '
             'and opening balance. Paginated for performance across thousands of '
             'records. Instantly searchable. Ideal for field reps who need to '
             'verify customer details before every visit or call.'),
            (AMBER,  'RP', 'Receivables & Payables',
             'Two-tab outstanding module -- every pending invoice with customer '
             'name, invoice number, date, due date, overdue days, and closing '
             'balance. Overdue entries highlighted clearly. Powerful search '
             'across name, invoice number, amount, and date field.'),
            (GREEN,  'SI', 'Sales Invoices',
             'Every sales invoice from Tally with full line-item detail: '
             'product names, quantities, unit rates, GST rates, discounts, '
             'and net totals. Generate a professional PDF Tax Invoice and '
             'share it instantly via WhatsApp, Email, or any app -- one tap.'),
            (PURPLE, 'PI', 'Purchase Invoices',
             'Mirror of the Sales module -- for all purchase and supplier bills. '
             'Track inward supply with full line-item breakdown per purchase '
             'bill. Generate and share formatted Purchase Invoice PDFs directly '
             'from the app, without needing desktop access.'),
            (RED,    'DY', 'Daybook (Daily Audit Trail)',
             'All daily vouchers -- Receipts, Payments, Sales, Journals -- for '
             'any selected date. Filter by date with a calendar picker. Search '
             'by voucher number, ledger name, or voucher type. Debit entries '
             'show as Inflow in green; Credit entries show as Outflow in red.'),
            (TEAL,   'AN', 'Analytics & Reports',
             'Three-tab intelligence engine: (1) Overview -- 14-day Daily Revenue '
             'vs. Gross Profit bar chart with total KPIs. (2) Velocity -- Fast '
             'and Slow moving items by sales volume, configurable from 30 to 365 '
             'days. (3) Dormant -- Dead Stock items and Dormant Customers who '
             'have not purchased within a configurable lookback period.'),
        ]

        mx, my = 14, 52
        cw, ch = 89, 47

        for i, (col, sym, title, desc) in enumerate(modules):
            bx = mx + (i % 2) * (cw + 4)
            by = my + (i // 2) * (ch + 5)

            self.fill_rect(bx, by, cw, ch, LIGHT_GREY)
            self.fill_rect(bx, by, 4, ch, col)

            # icon
            self.fill_rect(bx + 8, by + 8, 14, 14, col)
            self.t(8, bold=True)
            self.set_text_color(*WHITE)
            sw = self.get_string_width(sym)
            self.set_xy(bx + 8 + (14 - sw) / 2 - 0.5, by + 10.5)
            self.cell(sw + 1, 8, sym, align='C')

            # title
            self.t(10, bold=True)
            self.set_text_color(*DARK_TEXT)
            self.set_xy(bx + 25, by + 9)
            self.cell(cw - 28, 5.5, title)

            # desc
            self.t(8)
            self.set_text_color(*MID_TEXT)
            self.set_xy(bx + 8, by + 19)
            self.multi_cell(cw - 12, 3.9, desc)

    # ═════════════════════════════════════════════════════════════════════════
    #  PAGE 4 -- ANALYTICS + PDF INVOICING
    # ═════════════════════════════════════════════════════════════════════════
    def page_analytics(self):
        self.add_page()

        self.pill(14, 14, '  ANALYTICS ENGINE  ', BLUE, WHITE)

        self.set_xy(14, 25)
        self.t(19, bold=True)
        self.set_text_color(*DARK_TEXT)
        self.cell(0, 9, 'Business intelligence, not just data.')

        self.set_xy(14, 36)
        self.t(10, italic=True)
        self.set_text_color(*MID_TEXT)
        self.multi_cell(182, 5.5,
            'Heavy SQL computations run directly on the cloud database via PostgreSQL RPCs -- '
            'so your phone always gets fast, accurate results, even with hundreds of thousands of records.')

        # ─ Simulated bar chart visual ─────────────────────────────────────────
        self.fill_rect(14, 50, 182, 58, LIGHT_GREY)
        self.set_xy(18, 53)
        self.t(10, bold=True)
        self.set_text_color(*DARK_TEXT)
        self.cell(0, 6, 'Daily Revenue vs. Estimated Gross Profit  (14-Day Trend)')

        bar_data = [
            (22, 10), (35, 16), (28, 12), (42, 20), (38, 17),
            (50, 23), (31, 13), (45, 21), (29, 11), (55, 26),
            (47, 22), (60, 28), (52, 24), (65, 30),
        ]
        bx0, by0 = 18, 100
        max_h, max_val = 38, 65
        labels = ['D-13', 'D-12', 'D-11', 'D-10', 'D-9', 'D-8', 'D-7',
                  'D-6',  'D-5',  'D-4',  'D-3',  'D-2', 'D-1', 'Today']
        bar_w = 11
        for idx, (rev, pft) in enumerate(bar_data):
            bx = bx0 + idx * (bar_w + 2)
            rh = (rev / max_val) * max_h
            ph = (pft / max_val) * max_h
            self.fill_rect(bx,       by0 - rh, 5, rh, BLUE)
            self.fill_rect(bx + 5.5, by0 - ph, 5, ph, GREEN)
            self.t(5.5)
            self.set_text_color(*MID_TEXT)
            self.set_xy(bx - 1, by0 + 1)
            self.cell(bar_w, 3.5, labels[idx], align='C')

        # legend
        self.fill_rect(130, 54, 8, 4, BLUE)
        self.t(8)
        self.set_text_color(*DARK_TEXT)
        self.set_xy(140, 54)
        self.cell(0, 4, 'Revenue')
        self.fill_rect(130, 60, 8, 4, GREEN)
        self.set_xy(140, 60)
        self.cell(0, 4, 'Estimated Gross Profit')

        # ─ 5 Analytics descriptions ───────────────────────────────────────────
        analytics = [
            (BLUE,   '1.  Daily Revenue & Gross Profit',
             'Calculates per-day revenue (sum of invoice totals) and estimated gross profit '
             'using: (Unit Price - Standard Cost) x Quantity. Falls back to Item Rate if '
             'Standard Cost is unavailable. Rendered as a 14-day dual-bar chart with total KPIs.'),
            (TEAL,   '2.  Fast-Moving Items',
             'Identifies your best-selling products by total quantity sold over a configurable '
             'period (30, 90, 180, or 365 days). Uses a SQL RPC to aggregate sales, returning '
             'a ranked table -- essential for reorder planning and procurement decisions.'),
            (AMBER,  '3.  Slow-Moving Items',
             'Surfaces products with low sales volumes in the selected period. Helps identify '
             'dead weight in your product catalog -- useful for targeted promotions, pricing '
             'adjustments, or discontinuing underperforming items.'),
            (RED,    '4.  Dead Stock  (Unused Items)',
             'Lists inventory items with current stock > 0 but zero sales in the chosen '
             'lookback period. Calculates total Dead Stock Value (Qty x Rate), giving you '
             'the exact rupee amount of capital sitting idle in your warehouse.'),
            (PURPLE, '5.  Dormant Customers',
             'Identifies customers who have not placed any order in the configured period '
             '(30 / 90 / 180 / 365 days). Returns a complete list for targeted re-engagement '
             'campaigns, special offers, or proactive follow-up calls from your sales team.'),
        ]

        ay = 115
        for col, title, desc in analytics:
            self.fill_rect(14, ay, 182, 20, LIGHT_GREY)
            self.fill_rect(14, ay, 4, 20, col)
            self.t(10, bold=True)
            self.set_text_color(*DARK_TEXT)
            self.set_xy(22, ay + 3)
            self.cell(0, 5, title)
            self.t(8.5)
            self.set_text_color(*MID_TEXT)
            self.set_xy(22, ay + 9.5)
            self.multi_cell(170, 4.2, desc)
            ay += 23

        # ─ PDF Invoice section ────────────────────────────────────────────────
        self.h_line(14, ay + 3, 182, lw=0.5)
        ay += 9

        self.pill(14, ay, '  INSTANT PDF INVOICING  ', GREEN, WHITE)
        ay += 10

        self.set_xy(14, ay)
        self.t(14, bold=True)
        self.set_text_color(*DARK_TEXT)
        self.cell(0, 8, 'Generate & Share Professional Invoices in One Tap')
        ay += 10

        # Invoice mock visual (left side)
        iv = ay
        self.fill_rect(14, iv, 90, 52, LIGHT_GREY)
        self.fill_rect(14, iv, 90, 10, NAVY)
        self.t(9, bold=True)
        self.set_text_color(*WHITE)
        self.set_xy(17, iv + 1.5)
        self.cell(84, 5, 'TAX INVOICE  --  OrderX-Lite')
        self.t(7)
        self.set_xy(17, iv + 6.5)
        self.cell(84, 4, 'Invoice #: INV-2024-0892     Date: 10 Jul 2024')

        rows = [
            ('Item Description',         'Qty', 'Rate',     'GST', 'Amount'),
            ('Office Chair Ergonomic',    '5',   'Rs.4,500', '18%', 'Rs.26,550'),
            ('A4 Paper Ream (500 Sheets)','20',  'Rs.320',   '12%', 'Rs.7,168'),
            ('Printer Ink Cartridge',     '3',   'Rs.1,200', '18%', 'Rs.4,248'),
            ('NET TOTAL',                 '',    '',         '',    'Rs.37,966'),
        ]
        ty = iv + 13
        for ri, (n, q, r, g, a) in enumerate(rows):
            bg = (215, 228, 255) if ri == 0 else (250, 251, 253) if ri % 2 == 0 else WHITE
            self.fill_rect(16, ty, 86, 5.5, bg)
            self.t(6.5, bold=(ri in [0, 4]))
            self.set_text_color(*DARK_TEXT)
            self.set_xy(17, ty + 0.8)
            self.cell(38, 4, n)
            self.set_xy(55, ty + 0.8); self.cell(8,  4, q, align='C')
            self.set_xy(63, ty + 0.8); self.cell(13, 4, r, align='R')
            self.set_xy(76, ty + 0.8); self.cell(8,  4, g, align='C')
            self.set_xy(84, ty + 0.8); self.cell(13, 4, a, align='R')
            ty += 5.5

        # PDF features list (right side)
        self.set_xy(112, ay + 2)
        self.t(10, bold=True)
        self.set_text_color(*DARK_TEXT)
        self.cell(0, 6, "What's included in every PDF:")

        feats = [
            'Professional A4 Tax Invoice / Purchase Invoice layout',
            'Company name, invoice number, date, and party details',
            'Full line-item table: Qty, Rate, GST %, and Amount',
            'Auto-calculated Subtotal, Discount, GST, and Net Total',
            'Full Indian currency formatting with Rs. symbol',
            'Share via WhatsApp, Email, or any installed app -- one tap',
            'Download directly to device or browser (web version)',
        ]
        fy = ay + 10
        for feat in feats:
            self.circle(115, fy + 2, 1.5, GREEN)
            self.t(8.5)
            self.set_text_color(*DARK_TEXT)
            self.set_xy(119, fy)
            self.cell(0, 5.5, feat)
            fy += 6.5

    # =========================================================================
    #  PAGE 5 -- WHY ORDERX-LITE + CTA
    # =========================================================================
    def page_closing(self):
        self.add_page()

        self.pill(14, 14, '  WHY ORDERX-LITE  ', NAVY, WHITE)

        self.set_xy(14, 25)
        self.t(19, bold=True)
        self.set_text_color(*DARK_TEXT)
        self.cell(0, 9, 'Why businesses choose OrderX-Lite')

        reasons = [
            (BLUE,   'No Disruption to Tally',
             'OrderX-Lite does not replace Tally. It reads from it. Your accounting team '
             'continues working exactly as before -- no workflow changes, no voucher impact, '
             'no GST compliance risk. The app simply exposes Tally data to mobile users.'),
            (GREEN,  'Works for Any Business',
             'Whether you run a pharmacy, hardware shop, FMCG distributor, electronics '
             'dealer, garment manufacturer, or a service firm -- if you use Tally, '
             'OrderX-Lite works for you. The modules are universal.'),
            (TEAL,   'Multi-Company & Multi-User',
             'Manage multiple Tally companies from one app. Switch with a single tap. '
             'Role-based data isolation ensures each user only sees what they are '
             'authorized to access -- your data stays secure and private.'),
            (AMBER,  'Performance Optimized',
             'Heavy analytics (profit trends, stock velocity, dead stock) run as optimized '
             'server-side queries -- not on the mobile device. The app remains fast '
             'and snappy even with hundreds of thousands of invoice records.'),
            (PURPLE, 'Secure & Private',
             'All data stays in your own Supabase project. No third-party servers access '
             'your business data. Encryption in transit (HTTPS/TLS) and at rest. Row Level '
             'Security ensures complete tenancy isolation. Your data is yours, always.'),
            (RED,    'Cross-Platform',
             'One codebase -- available on Android, iOS, and Web. Whether your team uses '
             'iPhones, Android phones, or office browsers, everyone gets the same beautiful '
             'experience. The web version works on any browser for desktop access too.'),
        ]

        # Reason cards -- 6 items x 25mm = 150mm, starting at y=38 => ends at y=188
        ry = 38
        for col, title, desc in reasons:
            self.fill_rect(14, ry, 182, 22, LIGHT_GREY)
            self.fill_rect(14, ry, 4, 22, col)
            self.t(10.5, bold=True)
            self.set_text_color(*DARK_TEXT)
            self.set_xy(22, ry + 3)
            self.cell(0, 5.5, title)
            self.t(8.5)
            self.set_text_color(*MID_TEXT)
            self.set_xy(22, ry + 9.5)
            self.multi_cell(170, 4.2, desc)
            ry += 25

        # Thin divider before CTA
        self.h_line(14, ry + 3, 182, lw=0.4)

        # CTA Footer -- anchored at fixed y=200, fits entirely within A4 (297mm)
        cta_y = 200
        self.fill_rect(0, cta_y, 210, 82, NAVY)

        # Headline
        self.set_xy(14, cta_y + 10)
        self.t(20, bold=True)
        self.set_text_color(*WHITE)
        self.cell(0, 10, 'Ready to take your Tally data mobile?')

        # Sub-description
        self.set_xy(14, cta_y + 23)
        self.t(11)
        self.set_text_color(185, 210, 250)
        self.multi_cell(128, 6,
            'Book a free 15-minute live demo on your own Tally data.\n'
            'We will show you exactly what OrderX-Lite looks like with\n'
            'your real invoices, stock, and customers -- no commitment.')

        # Contact info (right column with pill labels)
        contacts = [
            ('+91 93800 13999',       'Phone  '),
            ('sales@aroundtally.com', 'Email  '),
            ('aroundtally.com',       'Web    '),
        ]
        cy2 = cta_y + 14
        for val, label in contacts:
            lw = self.get_string_width(label) + 6
            self.fill_rect(148, cy2, lw, 6.5, BLUE)
            self.t(7.5, bold=True)
            self.set_text_color(*WHITE)
            self.set_xy(148 + 2, cy2 + 0.8)
            self.cell(lw - 4, 5, label)
            self.t(9.5)
            self.set_text_color(*WHITE)
            self.set_xy(148 + lw + 2, cy2 + 0.5)
            self.cell(0, 5.5, val)
            cy2 += 13

        # 'Book a Demo' button
        btn_x, btn_y, btn_w = 14, cta_y + 55, 60
        self.fill_rect(btn_x, btn_y, btn_w, 11, BLUE)
        self.t(10, bold=True)
        self.set_text_color(*WHITE)
        self.set_xy(btn_x, btn_y + 1.5)
        self.cell(btn_w, 8, 'Book a Free Demo', align='C')

        # Tagline next to button
        self.t(8.5, italic=True)
        self.set_text_color(165, 190, 230)
        self.set_xy(btn_x + btn_w + 6, btn_y + 2.5)
        self.cell(0, 6, '15-min demo.  No commitment.  On your own Tally data.')

        # Legal disclaimer
        self.set_xy(14, cta_y + 75)
        self.t(7, italic=True)
        self.set_text_color(130, 155, 200)
        self.cell(0, 4,
            'OrderX-Lite is a product of AroundAI Software.  '
            'Tally is a registered trademark of Tally Solutions Pvt. Ltd.')


# ─────────────────────────────────────────────────────────────────────────────
def main():
    pdf = OrderXLitePDF(orientation='P', unit='mm', format='A4')
    pdf.set_auto_page_break(auto=True, margin=14)
    pdf.set_title('OrderX-Lite Product Brochure')
    pdf.set_author('AroundAI Software')

    pdf.page_cover()
    pdf.page_problem()
    pdf.page_modules()
    pdf.page_analytics()
    pdf.page_closing()

    out = 'OrderX_Lite_Brochure_v2.pdf'
    pdf.output(out)
    print(f'Success: Saved  ->  {out}')


if __name__ == '__main__':
    main()
