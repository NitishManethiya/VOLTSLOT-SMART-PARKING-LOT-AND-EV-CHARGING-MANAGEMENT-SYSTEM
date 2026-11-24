import os
import subprocess
import pymysql
import pymysql.cursors
from flask import Flask, render_template_string, request, redirect, url_for, flash

app = Flask(__name__)
app.secret_key = "voltslot-super-secret-key"

DB_CONFIG = {
    "host": "localhost",
    "user": "root",
    "password": "",
    "database": "voltparkdb",
    "cursorclass": pymysql.cursors.DictCursor,
    "autocommit": True
}

def get_db():
    return pymysql.connect(**DB_CONFIG)

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VoltSlot - Smart Parking & EV Dashboard</title>
        <script src="https://cdn.tailwindcss.com"></script>
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css" rel="stylesheet">
</head>
<body class="bg-slate-900 text-slate-100 min-h-screen font-sans">

        <header class="bg-slate-800/80 backdrop-blur border-b border-slate-700 sticky top-0 z-50">
        <div class="max-w-7xl mx-auto px-4 py-3 flex flex-wrap justify-between items-center gap-4">
            <div class="flex items-center space-x-3">
                <div class="w-10 h-10 rounded-xl bg-gradient-to-tr from-cyan-500 to-blue-600 flex items-center justify-center text-white shadow-lg shadow-cyan-500/30">
                    <i class="fa-solid fa-charging-station text-xl"></i>
                </div>
                <div>
                    <h1 class="text-xl font-bold tracking-tight bg-gradient-to-r from-cyan-400 via-sky-300 to-indigo-400 bg-clip-text text-transparent">
                        VoltSlot Management System
                    </h1>
                    <p class="text-xs text-slate-400">JIIT MCA DBMS Lab Project (VoltParkDB)</p>
                </div>
            </div>

            <div class="flex items-center gap-3">
                <form action="/reset" method="POST" onsubmit="return confirm('Reset database to clean initial seed data?');">
                    <button type="submit" class="px-3 py-1.5 text-xs font-semibold rounded-lg bg-slate-700 hover:bg-slate-600 text-slate-300 hover:text-white transition flex items-center gap-1.5 border border-slate-600">
                        <i class="fa-solid fa-rotate-left"></i> Reset DB
                    </button>
                </form>
                <div class="flex items-center gap-2 bg-emerald-950/60 border border-emerald-800/60 px-3 py-1.5 rounded-lg text-emerald-400 text-xs font-medium">
                    <span class="w-2 h-2 rounded-full bg-emerald-400 animate-pulse"></span>
                    MySQL 8.0 Live
                </div>
            </div>
        </div>
    </header>

    <main class="max-w-7xl mx-auto px-4 py-6 space-y-6">

                {% with messages = get_flashed_messages(with_categories=true) %}
          {% if messages %}
            {% for category, message in messages %}
              <div class="p-4 rounded-xl border text-sm font-medium flex items-center justify-between shadow-lg
                {% if category == 'success' %} bg-emerald-950/80 border-emerald-600 text-emerald-200
                {% elif category == 'error' %} bg-rose-950/80 border-rose-600 text-rose-200
                {% else %} bg-sky-950/80 border-sky-600 text-sky-200 {% endif %}">
                <div class="flex items-center gap-3">
                    <i class="fa-solid {% if category == 'success' %}fa-circle-check text-emerald-400{% else %}fa-circle-exclamation text-rose-400{% endif %} text-lg"></i>
                    <span>{{ message | safe }}</span>
                </div>
              </div>
            {% endfor %}
          {% endif %}
        {% endwith %}

                {% if invoice %}
        <div class="bg-gradient-to-br from-slate-800 to-slate-900 border-2 border-cyan-500 rounded-2xl p-6 shadow-2xl relative overflow-hidden">
            <div class="absolute top-0 right-0 transform translate-x-8 -translate-y-8 w-32 h-32 bg-cyan-500/10 rounded-full blur-2xl"></div>
            <div class="flex items-center justify-between border-b border-slate-700 pb-4 mb-4">
                <div class="flex items-center gap-3">
                    <div class="w-10 h-10 rounded-lg bg-emerald-500/20 text-emerald-400 flex items-center justify-center font-bold">
                        <i class="fa-solid fa-receipt text-xl"></i>
                    </div>
                    <div>
                        <h2 class="text-lg font-bold text-white">Invoice Generated Successfully! (Atomic Procedure)</h2>
                        <p class="text-xs text-slate-400">Bill ID #{{ invoice.invoice_id }} &bull; Ticket #{{ invoice.ticket_id }} &bull; Stored Procedure: <code>ProcessVehicleExit</code></p>
                    </div>
                </div>
                <span class="px-3 py-1 rounded-full text-xs font-semibold bg-emerald-500/20 text-emerald-300 border border-emerald-500/30">
                    <i class="fa-solid fa-check"></i> Paid & Settled
                </span>
            </div>

            <div class="grid grid-cols-2 sm:grid-cols-4 gap-4 text-xs mb-4">
                <div class="bg-slate-800/60 p-3 rounded-xl border border-slate-700/60">
                    <span class="text-slate-400 block mb-1">Vehicle</span>
                    <span class="font-bold text-white text-sm">{{ invoice.vehicle_no }}</span>
                    <span class="block text-slate-400">({{ invoice.owner_name }})</span>
                </div>
                <div class="bg-slate-800/60 p-3 rounded-xl border border-slate-700/60">
                    <span class="text-slate-400 block mb-1">Spot & Duration</span>
                    <span class="font-bold text-white text-sm">{{ invoice.spot_number }} (Fl {{ invoice.floor_no }})</span>
                    <span class="block text-slate-400">{{ invoice.billed_hours }} hrs @ ₹{{ invoice.rate_per_hour }}/hr</span>
                </div>
                <div class="bg-slate-800/60 p-3 rounded-xl border border-slate-700/60">
                    <span class="text-slate-400 block mb-1">EV Energy Used</span>
                    <span class="font-bold text-white text-sm">{{ invoice.ev_kwh_consumed }} kWh</span>
                    <span class="block text-slate-400">Cost: ₹{{ invoice.ev_fee }}</span>
                </div>
                <div class="bg-slate-800/60 p-3 rounded-xl border border-slate-700/60">
                    <span class="text-slate-400 block mb-1">Overstay Surcharge</span>
                    <span class="font-bold {% if invoice.overstay_penalty_fee > 0 %}text-amber-400{% else %}text-slate-300{% endif %} text-sm">
                        ₹{{ invoice.overstay_penalty_fee }}
                    </span>
                    <span class="block text-slate-400">{{ invoice.penalty_notes }}</span>
                </div>
            </div>

            <div class="flex items-center justify-between bg-slate-900/80 p-4 rounded-xl border border-slate-700">
                <div class="text-xs text-slate-400">
                    <span class="text-emerald-400 font-semibold"><i class="fa-solid fa-arrows-rotate"></i> Trigger Fired:</span> 
                    Spot <code>{{ invoice.spot_number }}</code> automatically transitioned back to <b>{{ invoice.spot_status_after_release }}</b>.
                </div>
                <div class="text-right">
                    <span class="text-xs text-slate-400 uppercase tracking-wider block">Total Amount</span>
                    <span class="text-2xl font-black text-cyan-400">₹{{ invoice.grand_total_amount }}</span>
                </div>
            </div>
        </div>
        {% endif %}

                {% if overstay_alerts %}
        <div class="bg-gradient-to-r from-amber-950/70 via-rose-950/60 to-slate-900 border border-amber-500/60 rounded-2xl p-4 shadow-xl">
            <div class="flex items-center justify-between mb-3">
                <div class="flex items-center gap-2 text-amber-400 font-bold">
                    <i class="fa-solid fa-triangle-exclamation text-lg animate-bounce"></i>
                    <span>Live Parking Violation Alerts (vw_OverstayingAlerts)</span>
                </div>
                <span class="text-xs bg-amber-500/20 border border-amber-500/40 text-amber-300 px-2.5 py-0.5 rounded-full">
                    {{ overstay_alerts | length }} Overstaying Vehicle(s)
                </span>
            </div>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
                {% for alert in overstay_alerts %}
                <div class="bg-slate-900/80 border border-amber-600/40 rounded-xl p-3 flex justify-between items-center text-xs">
                    <div>
                        <div class="flex items-center gap-2 mb-1">
                            <span class="font-bold text-white text-sm">{{ alert.vehicle_no }}</span>
                            <span class="px-2 py-0.5 rounded text-[10px] font-bold uppercase bg-amber-500/20 text-amber-300 border border-amber-500/30">
                                {{ alert.alert_status }}
                            </span>
                        </div>
                        <p class="text-slate-400">{{ alert.owner_name }} &bull; Call: <span class="text-cyan-400 font-mono">{{ alert.contact_number }}</span></p>
                        <p class="text-slate-400">Parked at <span class="text-slate-200 font-medium">{{ alert.spot_number }} ({{ alert.floor_location }})</span> for <span class="text-amber-400 font-semibold">{{ alert.hours_parked_so_far }} hours</span></p>
                    </div>
                    <div class="text-right">
                        <span class="text-[10px] text-slate-400 block uppercase">Accrued Bill</span>
                        <span class="text-base font-bold text-amber-400">₹{{ alert.estimated_accrued_bill }}</span>
                    </div>
                </div>
                {% endfor %}
            </div>
        </div>
        {% endif %}

                <div class="grid grid-cols-1 lg:grid-cols-12 gap-6">

                        <div class="lg:col-span-8 space-y-6">

                                <div class="bg-slate-800/70 border border-slate-700/80 rounded-2xl p-5 shadow-xl">
                    <div class="flex items-center justify-between mb-4">
                        <div>
                            <h2 class="text-base font-bold text-white flex items-center gap-2">
                                <i class="fa-solid fa-square-parking text-cyan-400"></i>
                                Real-Time Parking Bay Layout
                            </h2>
                            <p class="text-xs text-slate-400">Auto-updated via <code>AFTER INSERT</code> & <code>AFTER UPDATE</code> Triggers</p>
                        </div>
                        <div class="flex items-center gap-4 text-xs">
                            <div class="flex items-center gap-1.5"><span class="w-3 h-3 rounded-md bg-emerald-500"></span> Available</div>
                            <div class="flex items-center gap-1.5"><span class="w-3 h-3 rounded-md bg-rose-500"></span> Occupied</div>
                        </div>
                    </div>

                                        <div class="mb-4">
                        <span class="text-xs font-semibold text-slate-400 uppercase tracking-wider block mb-2">Floor 1</span>
                        <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
                            {% for spot in spots if spot.floor_no == 1 %}
                            <div class="p-3 rounded-xl border transition-all duration-200 
                                {% if spot.status == 'Available' %} bg-emerald-950/30 border-emerald-700/60 hover:border-emerald-500
                                {% else %} bg-rose-950/30 border-rose-700/60 hover:border-rose-500 {% endif %}">
                                <div class="flex items-center justify-between mb-1">
                                    <span class="font-bold text-sm text-white">{{ spot.spot_number }}</span>
                                    <span class="text-[10px] px-2 py-0.5 rounded font-semibold
                                        {% if spot.spot_type == 'EV' %} bg-cyan-500/20 text-cyan-300 border border-cyan-500/30
                                        {% elif spot.spot_type == 'SUV' %} bg-purple-500/20 text-purple-300 border border-purple-500/30
                                        {% else %} bg-slate-700 text-slate-300 {% endif %}">
                                        {% if spot.spot_type == 'EV' %}<i class="fa-solid fa-bolt mr-1"></i>{% endif %}{{ spot.spot_type }}
                                    </span>
                                </div>
                                <div class="flex items-center justify-between text-xs">
                                    <span class="{% if spot.status == 'Available' %}text-emerald-400{% else %}text-rose-400{% endif %} font-medium">
                                        {{ spot.status }}
                                    </span>
                                </div>
                            </div>
                            {% endfor %}
                        </div>
                    </div>

                                        <div>
                        <span class="text-xs font-semibold text-slate-400 uppercase tracking-wider block mb-2">Floor 2</span>
                        <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
                            {% for spot in spots if spot.floor_no == 2 %}
                            <div class="p-3 rounded-xl border transition-all duration-200 
                                {% if spot.status == 'Available' %} bg-emerald-950/30 border-emerald-700/60 hover:border-emerald-500
                                {% else %} bg-rose-950/30 border-rose-700/60 hover:border-rose-500 {% endif %}">
                                <div class="flex items-center justify-between mb-1">
                                    <span class="font-bold text-sm text-white">{{ spot.spot_number }}</span>
                                    <span class="text-[10px] px-2 py-0.5 rounded font-semibold
                                        {% if spot.spot_type == 'EV' %} bg-cyan-500/20 text-cyan-300 border border-cyan-500/30
                                        {% elif spot.spot_type == 'SUV' %} bg-purple-500/20 text-purple-300 border border-purple-500/30
                                        {% else %} bg-slate-700 text-slate-300 {% endif %}">
                                        {% if spot.spot_type == 'EV' %}<i class="fa-solid fa-bolt mr-1"></i>{% endif %}{{ spot.spot_type }}
                                    </span>
                                </div>
                                <div class="flex items-center justify-between text-xs">
                                    <span class="{% if spot.status == 'Available' %}text-emerald-400{% else %}text-rose-400{% endif %} font-medium">
                                        {{ spot.status }}
                                    </span>
                                </div>
                            </div>
                            {% endfor %}
                        </div>
                    </div>

                </div>

                                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                                        <div class="bg-slate-800/70 border border-slate-700/80 rounded-2xl p-4 shadow-xl">
                        <h3 class="text-xs font-bold text-slate-300 uppercase tracking-wider mb-3 flex items-center gap-1.5">
                            <i class="fa-solid fa-chart-pie text-cyan-400"></i>
                            Floor Availability (vw_LiveAvailableSpots)
                        </h3>
                        <div class="overflow-x-auto">
                            <table class="w-full text-left text-xs">
                                <thead>
                                    <tr class="border-b border-slate-700 text-slate-400">
                                        <th class="pb-2">Floor</th>
                                        <th class="pb-2">Type</th>
                                        <th class="pb-2">Avail</th>
                                        <th class="pb-2">Occ</th>
                                        <th class="pb-2 text-right">% Avail</th>
                                    </tr>
                                </thead>
                                <tbody class="divide-y divide-slate-700/50">
                                    {% for row in live_spot_stats %}
                                    <tr>
                                        <td class="py-1.5 font-medium text-slate-200">Fl {{ row.floor_number }}</td>
                                        <td class="py-1.5 text-slate-400">{{ row.spot_type }}</td>
                                        <td class="py-1.5 text-emerald-400 font-semibold">{{ row.available_spots }}</td>
                                        <td class="py-1.5 text-rose-400 font-semibold">{{ row.occupied_spots }}</td>
                                        <td class="py-1.5 text-right font-mono text-cyan-400">{{ row.availability_pct }}%</td>
                                    </tr>
                                    {% endfor %}
                                </tbody>
                            </table>
                        </div>
                    </div>

                                        <div class="bg-slate-800/70 border border-slate-700/80 rounded-2xl p-4 shadow-xl">
                        <h3 class="text-xs font-bold text-slate-300 uppercase tracking-wider mb-3 flex items-center gap-1.5">
                            <i class="fa-solid fa-coins text-amber-400"></i>
                            Daily Revenue (vw_DailyRevenueReport)
                        </h3>
                        <div class="overflow-x-auto">
                            <table class="w-full text-left text-xs">
                                <thead>
                                    <tr class="border-b border-slate-700 text-slate-400">
                                        <th class="pb-2">Date</th>
                                        <th class="pb-2">Bills</th>
                                        <th class="pb-2">Parking</th>
                                        <th class="pb-2">EV Power</th>
                                        <th class="pb-2 text-right">Total</th>
                                    </tr>
                                </thead>
                                <tbody class="divide-y divide-slate-700/50">
                                    {% for row in revenue_report %}
                                    <tr>
                                        <td class="py-1.5 text-slate-300">{{ row.revenue_date }}</td>
                                        <td class="py-1.5 text-slate-400">{{ row.total_settled_tickets }}</td>
                                        <td class="py-1.5 text-slate-300 font-mono">₹{{ row.total_parking_revenue }}</td>
                                        <td class="py-1.5 text-cyan-400 font-mono">₹{{ row.total_ev_charging_revenue }}</td>
                                        <td class="py-1.5 text-right font-bold text-amber-400 font-mono">₹{{ row.grand_total_revenue }}</td>
                                    </tr>
                                    {% endfor %}
                                </tbody>
                            </table>
                        </div>
                    </div>
                </div>

            </div>

                        <div class="lg:col-span-4 space-y-6">

                                <div class="bg-slate-800/70 border border-slate-700/80 rounded-2xl p-5 shadow-xl">
                    <h3 class="text-sm font-bold text-white mb-1 flex items-center gap-2">
                        <i class="fa-solid fa-arrow-right-to-bracket text-emerald-400"></i>
                        Vehicle Entry (Check-In)
                    </h3>
                    <p class="text-xs text-slate-400 mb-4">Inserts into <code>Parking_Tickets</code> & triggers <code>trg_auto_occupy_spot</code></p>

                    <form action="/checkin" method="POST" class="space-y-3">
                        <div>
                            <label class="block text-xs font-semibold text-slate-300 mb-1">Select Vehicle</label>
                            <select name="vehicle_id" required class="w-full bg-slate-900 border border-slate-700 rounded-xl px-3 py-2 text-xs text-white focus:outline-none focus:border-cyan-500">
                                {% for v in registered_vehicles %}
                                <option value="{{ v.vehicle_id }}">
                                    {{ v.vehicle_no }} ({{ v.vehicle_type }} &bull; {{ v.owner_name }})
                                </option>
                                {% endfor %}
                            </select>
                        </div>

                        <div>
                            <label class="block text-xs font-semibold text-slate-300 mb-1">Select Available Spot</label>
                            <select name="spot_id" required class="w-full bg-slate-900 border border-slate-700 rounded-xl px-3 py-2 text-xs text-white focus:outline-none focus:border-cyan-500">
                                {% for s in available_spots %}
                                <option value="{{ s.spot_id }}">
                                    {{ s.spot_number }} (Floor {{ s.floor_no }} &bull; {{ s.spot_type }})
                                </option>
                                {% endfor %}
                            </select>
                        </div>

                        <div>
                            <label class="block text-xs font-semibold text-slate-300 mb-1">Simulated Past Duration (Minutes)</label>
                            <input type="number" name="minutes_ago" value="120" min="0" max="2880"
                                class="w-full bg-slate-900 border border-slate-700 rounded-xl px-3 py-2 text-xs text-white focus:outline-none focus:border-cyan-500">
                            <span class="text-[10px] text-slate-500">E.g., 120 mins = 2 hours parked ago</span>
                        </div>

                        <button type="submit" class="w-full py-2.5 px-4 bg-emerald-600 hover:bg-emerald-500 text-white font-semibold text-xs rounded-xl shadow-lg shadow-emerald-600/30 transition flex items-center justify-center gap-2">
                            <i class="fa-solid fa-car"></i> Issue Ticket & Occupy Spot
                        </button>
                    </form>
                </div>

                                <div class="bg-slate-800/70 border border-slate-700/80 rounded-2xl p-5 shadow-xl">
                    <h3 class="text-sm font-bold text-white mb-1 flex items-center gap-2">
                        <i class="fa-solid fa-arrow-right-from-bracket text-cyan-400"></i>
                        Vehicle Exit & Bill Checkout
                    </h3>
                    <p class="text-xs text-slate-400 mb-4">Executes <code>ProcessVehicleExit</code> & triggers <code>trg_auto_free_spot</code></p>

                    {% if active_tickets %}
                    <form action="/checkout" method="POST" class="space-y-3">
                        <div>
                            <label class="block text-xs font-semibold text-slate-300 mb-1">Select Active Ticket to Exit</label>
                            <select name="ticket_id" required class="w-full bg-slate-900 border border-slate-700 rounded-xl px-3 py-2 text-xs text-white focus:outline-none focus:border-cyan-500">
                                {% for t in active_tickets %}
                                <option value="{{ t.ticket_id }}">
                                </option>
                                {% endfor %}
                            </select>
                        </div>

                        <div>
                            <label class="block text-xs font-semibold text-slate-300 mb-1">EV Power Consumed (kWh)</label>
                            <input type="number" step="0.1" name="kwh_consumed" value="18.5" min="0" max="100"
                                class="w-full bg-slate-900 border border-slate-700 rounded-xl px-3 py-2 text-xs text-white focus:outline-none focus:border-cyan-500">
                            <span class="text-[10px] text-slate-500">Calculated only if vehicle type is EV (₹12/kWh)</span>
                        </div>

                        <button type="submit" class="w-full py-2.5 px-4 bg-cyan-600 hover:bg-cyan-500 text-white font-semibold text-xs rounded-xl shadow-lg shadow-cyan-600/30 transition flex items-center justify-center gap-2">
                            <i class="fa-solid fa-calculator"></i> Run Exit Procedure & Bill
                        </button>
                    </form>
                    {% else %}
                    <div class="p-4 rounded-xl bg-slate-900/60 border border-slate-700/60 text-center text-xs text-slate-400">
                        <i class="fa-solid fa-circle-info mb-1 text-slate-500 text-sm block"></i>
                        No active vehicles currently parked. Use the check-in form above to park a vehicle!
                    </div>
                    {% endif %}
                </div>

            </div>

        </div>

    </main>

        <footer class="mt-8 border-t border-slate-800 py-4 text-center text-xs text-slate-500">
        VoltSlot DBMS Project &bull; Jaypee Institute of Information Technology (JIIT), Noida &bull; MySQL 8.0 & Flask
    </footer>

</body>
</html>
"""

@app.route("/")
def index():
    conn = get_db()
    with conn.cursor() as cur:
        cur.execute("SELECT * FROM Parking_Spots ORDER BY floor_no, spot_number;")
        spots = cur.fetchall()

        cur.execute("SELECT spot_id, spot_number, spot_type, floor_no FROM Parking_Spots WHERE status = 'Available' ORDER BY floor_no, spot_number;")
        available_spots = cur.fetchall()

        cur.execute("SELECT vehicle_id, vehicle_no, owner_name, vehicle_type, registration_category FROM Vehicles ORDER BY vehicle_no;")
        registered_vehicles = cur.fetchall()

        cur.execute("""
            SELECT pt.ticket_id, pt.spot_id, pt.entry_time, v.vehicle_no, v.owner_name, v.vehicle_type, v.registration_category, ps.spot_number, ps.floor_no
            FROM Parking_Tickets pt
            JOIN Vehicles v ON pt.vehicle_id = v.vehicle_id
            JOIN Parking_Spots ps ON pt.spot_id = ps.spot_id
            WHERE pt.ticket_status = 'Active'
            ORDER BY pt.entry_time DESC;
        """)
        active_tickets = cur.fetchall()

        cur.execute("SELECT * FROM vw_OverstayingAlerts;")
        overstay_alerts = cur.fetchall()

        cur.execute("SELECT * FROM vw_LiveAvailableSpots;")
        live_spot_stats = cur.fetchall()

        cur.execute("SELECT * FROM vw_DailyRevenueReport LIMIT 5;")
        revenue_report = cur.fetchall()

    conn.close()
    return render_template_string(
        HTML_TEMPLATE,
        spots=spots,
        available_spots=available_spots,
        registered_vehicles=registered_vehicles,
        active_tickets=active_tickets,
        overstay_alerts=overstay_alerts,
        live_spot_stats=live_spot_stats,
        revenue_report=revenue_report,
        invoice=None
    )

@app.route("/checkin", methods=["POST"])
def checkin():
    vehicle_id = request.form.get("vehicle_id")
    spot_id = request.form.get("spot_id")
    minutes_ago = int(request.form.get("minutes_ago", 0))

    conn = get_db()
    with conn.cursor() as cur:
        cur.execute("""
            INSERT INTO Parking_Tickets (spot_id, vehicle_id, entry_time, ticket_status)
            VALUES (%s, %s, NOW() - INTERVAL %s MINUTE, 'Active');
        """, (spot_id, vehicle_id, minutes_ago))
        ticket_id = cur.lastrowid
    conn.close()

    flash(f"Vehicle checked in! Ticket <b>#{ticket_id}</b> issued. Notice how Trigger <code>trg_auto_occupy_spot</code> automatically set Spot to <b>Occupied</b>!", "success")
    return redirect(url_for("index"))

@app.route("/checkout", methods=["POST"])
def checkout():
    ticket_id = int(request.form.get("ticket_id"))
    kwh_consumed = float(request.form.get("kwh_consumed", 0.0))

    conn = get_db()
    with conn.cursor() as cur:
        cur.execute("""
            SELECT v.vehicle_type 
            FROM Parking_Tickets pt 
            JOIN Vehicles v ON pt.vehicle_id = v.vehicle_id 
            WHERE pt.ticket_id = %s;
        """, (ticket_id,))
        veh = cur.fetchone()

        if veh and veh["vehicle_type"] == "EV" and kwh_consumed > 0:
            cur.execute("""
                INSERT INTO EV_Charging_Logs (ticket_id, kwh_consumed, charging_status, start_time, end_time)
                VALUES (%s, %s, 'Completed', NOW() - INTERVAL 1 HOUR, NOW())
                ON DUPLICATE KEY UPDATE kwh_consumed = VALUES(kwh_consumed), charging_status = 'Completed';
            """, (ticket_id, kwh_consumed))

        cur.execute("CALL ProcessVehicleExit(%s);", (ticket_id,))
        invoice = cur.fetchone()

        cur.execute("SELECT * FROM Parking_Spots ORDER BY floor_no, spot_number;")
        spots = cur.fetchall()
        cur.execute("SELECT spot_id, spot_number, spot_type, floor_no FROM Parking_Spots WHERE status = 'Available' ORDER BY floor_no, spot_number;")
        available_spots = cur.fetchall()
        cur.execute("SELECT vehicle_id, vehicle_no, owner_name, vehicle_type, registration_category FROM Vehicles ORDER BY vehicle_no;")
        registered_vehicles = cur.fetchall()
        cur.execute("""
            SELECT pt.ticket_id, pt.spot_id, pt.entry_time, v.vehicle_no, v.owner_name, v.vehicle_type, v.registration_category, ps.spot_number, ps.floor_no
            FROM Parking_Tickets pt
            JOIN Vehicles v ON pt.vehicle_id = v.vehicle_id
            JOIN Parking_Spots ps ON pt.spot_id = ps.spot_id
            WHERE pt.ticket_status = 'Active'
            ORDER BY pt.entry_time DESC;
        """)
        active_tickets = cur.fetchall()
        cur.execute("SELECT * FROM vw_OverstayingAlerts;")
        overstay_alerts = cur.fetchall()
        cur.execute("SELECT * FROM vw_LiveAvailableSpots;")
        live_spot_stats = cur.fetchall()
        cur.execute("SELECT * FROM vw_DailyRevenueReport LIMIT 5;")
        revenue_report = cur.fetchall()

    conn.close()
    flash(f"Checkout completed for Ticket <b>#{ticket_id}</b>! Trigger <code>trg_auto_free_spot</code> automatically released the spot.", "success")
    return render_template_string(
        HTML_TEMPLATE,
        spots=spots,
        available_spots=available_spots,
        registered_vehicles=registered_vehicles,
        active_tickets=active_tickets,
        overstay_alerts=overstay_alerts,
        live_spot_stats=live_spot_stats,
        revenue_report=revenue_report,
        invoice=invoice
    )

@app.route("/reset", methods=["POST"])
def reset():
    script_path = os.path.join(os.path.dirname(__file__), "voltslot_master.sql")
    mysql_cmd = r"C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe"
    try:
        with open(script_path, "r", encoding="utf-8") as f:
            subprocess.run([mysql_cmd, "-u", "root"], input=f.read(), text=True, check=True)
        flash("Database has been reset to clean initial seed data!", "info")
    except Exception as e:
        flash(f"Error resetting database: {e}", "error")
    return redirect(url_for("index"))

if __name__ == "__main__":
    print("===============================================================")
    print(" VoltSlot UI Dashboard is running on: http://127.0.0.1:5000")
    print(" Press Ctrl+C in terminal to stop.")
    print("===============================================================")
    app.run(host="127.0.0.1", port=5000, debug=True)
