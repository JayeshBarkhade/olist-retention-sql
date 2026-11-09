#!/usr/bin/env python3
"""
Generate a SYNTHETIC e-commerce dataset shaped like the public Olist (Brazilian
marketplace) dataset: same 8 table names and column names, same quirks
(customer_id is per ORDER, customer_unique_id is the real person; duplicate
reviews; bad timestamps; empty strings for NULL; messy city names).

This is NOT real customer data. Behavioural effects (e.g. late delivery lowers
repeat purchase) are assumptions written into this generator, so any "finding"
on this data illustrates the SQL method, not real-world evidence.
To use the real data instead, drop the real Olist CSVs into data/ (see README).

Usage: python3 generate_synthetic_olist.py [out_dir] [n_customers]
Deterministic: fixed seed, same output every run.
"""
import bisect, hashlib, os, random, sys
import numpy as np
import pandas as pd

SEED = 42
OUT = sys.argv[1] if len(sys.argv) > 1 else "data"
N_CUSTOMERS = int(sys.argv[2]) if len(sys.argv) > 2 else 80000
N_PRODUCTS, N_SELLERS = 3300, 950
START = pd.Timestamp("2017-01-01")
END = pd.Timestamp("2018-08-31 23:59:59")   # data cut-off (right-censoring!)

rnd = random.Random(SEED)
nrng = np.random.default_rng(SEED)
os.makedirs(OUT, exist_ok=True)


def hid(prefix, n):
    return hashlib.md5(f"{prefix}-{n}".encode()).hexdigest()


# ---------------------------------------------------------------- categories
CATS = [
 ("cama_mesa_banho","bed_bath_table"),("beleza_saude","health_beauty"),("esporte_lazer","sports_leisure"),
 ("informatica_acessorios","computers_accessories"),("moveis_decoracao","furniture_decor"),
 ("utilidades_domesticas","housewares"),("relogios_presentes","watches_gifts"),("telefonia","telephony"),
 ("automotivo","auto"),("brinquedos","toys"),("cool_stuff","cool_stuff"),("ferramentas_jardim","garden_tools"),
 ("perfumaria","perfumery"),("bebes","baby"),("eletronicos","electronics"),("papelaria","stationery"),
 ("fashion_bolsas_e_acessorios","fashion_bags_accessories"),("pet_shop","pet_shop"),
 ("moveis_escritorio","office_furniture"),("consoles_games","consoles_games"),
 ("malas_acessorios","luggage_accessories"),("construcao_ferramentas_construcao","construction_tools_construction"),
 ("eletrodomesticos","home_appliances"),("instrumentos_musicais","musical_instruments"),
 ("eletroportateis","small_appliances"),("casa_construcao","home_construction"),
 ("livros_interesse_geral","books_general_interest"),("alimentos","food"),("musica","music"),("artes","art"),
 ("flores","flowers"),("fashion_roupa_masculina","fashion_male_clothing"),("pc_gamer","pc_gamer"),
 ("casa_conforto","home_comfort"),("la_cuisine","la_cuisine"),("cds_dvds_musicais","cds_dvds_musicals"),
 ("seguros_e_servicos","security_and_services"),("fashion_esporte","fashion_sport"),
 ("artes_e_artesanato","arts_and_craftmanship"),
 ("portateis_cozinha_e_preparadores_de_alimentos","portable_kitchen_and_food_preparers"),
]
cat_w = np.array([1.0 / (i + 1) ** 1.25 for i in range(len(CATS))])
cat_w[28:] *= 0.02          # long tail of tiny categories (real Olist has some with only a handful of orders)
cat_w /= cat_w.sum()
cat_cum = np.cumsum(cat_w).tolist()
cat_scale = nrng.uniform(0.5, 2.2, len(CATS))

# ------------------------------------------------------------------ products
counts = np.maximum(2, np.round(N_PRODUCTS * cat_w)).astype(int)
prod_rows, prod_by_cat = [], {i: [] for i in range(len(CATS))}
pid = 0
for ci, n in enumerate(counts):
    for _ in range(n):
        price = float(np.clip(np.exp(nrng.normal(np.log(60 * cat_scale[ci]), 0.7)), 4, 3000))
        weight = int(np.clip(np.exp(nrng.normal(6.6, 0.9)), 50, 30000))
        prod_rows.append(dict(
            product_id=hid("p", pid),
            product_category_name=("" if rnd.random() < 0.015 else CATS[ci][0]),
            product_name_lenght=int(nrng.integers(20, 70)), product_description_lenght=int(nrng.integers(80, 2000)),
            product_photos_qty=int(nrng.integers(1, 8)), product_weight_g=weight,
            product_length_cm=int(nrng.integers(10, 60)), product_height_cm=int(nrng.integers(2, 40)),
            product_width_cm=int(nrng.integers(8, 50))))
        prod_by_cat[ci].append((pid, round(price, 2), weight))
        pid += 1
products = pd.DataFrame(prod_rows)
pcum = {}
for ci, lst in prod_by_cat.items():
    w = np.array([1.0 / (r + 1) ** 0.9 for r in range(len(lst))]); w /= w.sum()
    pcum[ci] = np.cumsum(w).tolist()

# ------------------------------------------------------------------- states
ST = {"SP":.42,"RJ:":0,"RJ":.13,"MG":.117,"RS":.056,"PR":.052,"SC":.037,"BA":.034,"DF":.022,"GO":.021,"ES":.020,
      "PE":.017,"CE":.013,"PA":.010,"MT":.009,"MA":.007,"MS":.007,"PB":.005,"PI":.005,"RN":.005,"AL":.004,
      "SE":.004,"TO":.003,"RO":.003,"AM":.002,"AC":.001,"AP":.001,"RR":.001}
ST.pop("RJ:")
st_names = list(ST); st_p = np.array([ST[s] for s in st_names]); st_p /= st_p.sum()
st_cum = np.cumsum(st_p).tolist()
TRANSIT = {"SP":4.5,"RJ":8,"MG":8,"PR":8,"SC":9,"RS":10,"DF":9,"GO":10,"ES":9,"BA":13,"PE":14,"CE":15,"PA":17,
           "MT":13,"MA":16,"MS":11,"PB":15,"PI":16,"RN":15,"AL":15,"SE":14,"TO":14,"RO":18,"AM":22,"AC":22,
           "AP":22,"RR":25}
CITIES = {"SP":["sao paulo","campinas","guarulhos","santo andre","osasco","ribeirao preto","sorocaba","sao bernardo do campo"],
          "RJ":["rio de janeiro","niteroi","duque de caxias","nova iguacu","petropolis"],
          "MG":["belo horizonte","uberlandia","contagem","juiz de fora","betim"],
          "RS":["porto alegre","caxias do sul","pelotas","canoas"],"PR":["curitiba","londrina","maringa","ponta grossa"],
          "SC":["florianopolis","joinville","blumenau"],"BA":["salvador","feira de santana","vitoria da conquista"],
          "DF":["brasilia"],"GO":["goiania","anapolis"],"ES":["vitoria","vila velha"],"PE":["recife","olinda"],"CE":["fortaleza"]}
ACCENT = {"sao paulo":"são paulo","brasilia":"brasília","goiania":"goiânia","vitoria":"vitória","niteroi":"niterói",
          "maringa":"maringá","florianopolis":"florianópolis","ribeirao preto":"ribeirão preto"}
def city_for(st):
    c = rnd.choice(CITIES.get(st, [f"cidade {st.lower()}"]))
    r = rnd.random()
    if r < 0.03: return c.upper()
    if r < 0.06: return c + " "
    if r < 0.08 and c in ACCENT: return ACCENT[c]
    return c
def zip5(): return f"{rnd.randint(1000, 99999):05d}"

# ------------------------------------------------------------------- sellers
seller_rows = []
for s in range(N_SELLERS):
    st = "SP" if rnd.random() < 0.6 else st_names[bisect.bisect(st_cum, rnd.random()) % len(st_names)]
    seller_rows.append(dict(seller_id=hid("s", s), seller_zip_code_prefix=zip5(),
                            seller_city=rnd.choice(CITIES.get(st, [f"cidade {st.lower()}"])), seller_state=st))
sellers = pd.DataFrame(seller_rows)
sw = np.array([1.0 / (i + 1) ** 0.7 for i in range(N_SELLERS)]); sw /= sw.sum()
seller_cum = np.cumsum(sw).tolist()
prod_seller = [bisect.bisect(seller_cum, rnd.random()) % N_SELLERS for _ in range(len(products))]

# ------------------------------------------------- person first-purchase dates
n_months = 20  # 2017-01 .. 2018-08
mw = np.linspace(1, 6, n_months); mw[10] *= 1.6  # Nov-2017 spike
mw /= mw.sum(); mcum = np.cumsum(mw).tolist()
month_starts = pd.date_range(START, periods=n_months, freq="MS")

def first_ts():
    m = bisect.bisect(mcum, rnd.random()) % n_months
    ms = month_starts[m]
    days_in = (ms + pd.offsets.MonthEnd(0)).day
    ts = ms + pd.Timedelta(days=rnd.randrange(days_in), hours=rnd.randrange(7, 23), minutes=rnd.randrange(60),
                           seconds=rnd.randrange(60))
    return min(ts, END - pd.Timedelta(days=1))

# --------------------------------------------------------------- order engine
orders, items, pays, reviews, customers = [], [], [], [], []
PHRASES = {1:["Não recebi o produto","Entrega atrasada, péssimo","Produto veio com defeito"],
           2:["Demorou muito para chegar","Produto abaixo do esperado"],
           3:["Produto ok, entrega demorada","Mais ou menos"],
           4:["Bom produto","Chegou no prazo, recomendo"],
           5:["Recomendo","Chegou antes do prazo","Produto de boa qualidade","Excelente, muito satisfeito"]}
oc = 0
SCORE_ON = [0.03, 0.03, 0.08, 0.22, 0.64]
SCORE_LATE = [0.35, 0.20, 0.15, 0.15, 0.15]
PAY_TYPES = ["credit_card", "boleto", "voucher", "debit_card"]; PAY_CUM = np.cumsum([.75, .19, .04, .02]).tolist()

def fmt(t): return "" if t is None else t.strftime("%Y-%m-%d %H:%M:%S")

def build_order(uid, st, city, zp, ts):
    """Create one order; return (status, delivered_ts, late, score)."""
    global oc
    oc += 1
    oid, cid = hid("o", oc), hid("c", oc)
    customers.append(dict(customer_id=cid, customer_unique_id=uid, customer_zip_code_prefix=zp,
                          customer_city=city_for(st) if rnd.random() < 0.15 else city, customer_state=st))
    r = rnd.random()
    status = ("canceled" if r < .008 else "unavailable" if r < .012 else "invoiced" if r < .015
              else "processing" if r < .018 else "shipped" if r < .024 else "delivered")
    approved = ts + pd.Timedelta(hours=rnd.expovariate(1 / 6) + 0.1) if status != "unavailable" or rnd.random() < .5 else None
    mean = TRANSIT[st] * (1.4 if pd.Timestamp("2017-11-10") <= ts <= pd.Timestamp("2017-12-31") else 1.0)
    transit = rnd.lognormvariate(np.log(mean) - 0.5 * 0.55 ** 2, 0.55)
    if rnd.random() < 0.035: transit += rnd.uniform(8, 25)
    est_days = int(np.ceil(TRANSIT[st] * 1.6 + 4))
    est = (ts.normalize() + pd.Timedelta(days=est_days))
    carrier = (approved + pd.Timedelta(days=rnd.uniform(1, 3))) if approved is not None else None
    delivered = ts + pd.Timedelta(days=transit)
    if carrier is not None and delivered <= carrier: delivered = carrier + pd.Timedelta(days=1.0)
    if status == "delivered" and delivered > END:       # still in transit at cut-off
        status, delivered = "shipped", None
    if status != "delivered": delivered = None
    if status in ("canceled", "unavailable", "invoiced", "processing"): carrier = None
    late = bool(delivered is not None and delivered.normalize() > est)
    orders.append(dict(order_id=oid, customer_id=cid, order_status=status, order_purchase_timestamp=fmt(ts),
                       order_approved_at=fmt(approved), order_delivered_carrier_date=fmt(carrier),
                       order_delivered_customer_date=fmt(delivered), order_estimated_delivery_date=fmt(est)))
    # items
    has_items = status != "unavailable" and not (status == "canceled" and rnd.random() < .15)
    total = 0.0
    if has_items:
        r = rnd.random(); n_it = 1 if r < .78 else 2 if r < .93 else 3 if r < .98 else 4
        base_fr = 12 if st == "SP" else 18 + TRANSIT[st] * 0.9
        for k in range(1, n_it + 1):
            ci = bisect.bisect(cat_cum, rnd.random()) % len(CATS)
            pi_local = bisect.bisect(pcum[ci], rnd.random()) % len(prod_by_cat[ci])
            gp, base_price, wt = prod_by_cat[ci][pi_local]
            price = round(base_price * rnd.uniform(0.9, 1.1), 2)
            fr = round(base_fr * rnd.uniform(0.8, 1.2) + wt / 1000 * 1.2, 2)
            items.append(dict(order_id=oid, order_item_id=k, product_id=hid("p", gp),
                              seller_id=hid("s", prod_seller[gp]),
                              shipping_limit_date=fmt((approved or ts) + pd.Timedelta(days=rnd.randint(2, 6))),
                              price=price, freight_value=fr))
            total += price + fr
        total = round(total, 2)
        ptype = PAY_TYPES[bisect.bisect(PAY_CUM, rnd.random()) % 4]
        inst = 1 if ptype != "credit_card" else (1 if rnd.random() < .5 else rnd.randint(2, 10))
        if rnd.random() < .05 and total > 40:
            v = round(total * rnd.uniform(.2, .6), 2)
            pays.append(dict(order_id=oid, payment_sequential=1, payment_type="voucher", payment_installments=1, payment_value=v))
            pays.append(dict(order_id=oid, payment_sequential=2, payment_type="credit_card", payment_installments=inst,
                             payment_value=round(total - v, 2)))
        else:
            pays.append(dict(order_id=oid, payment_sequential=1, payment_type=ptype, payment_installments=inst, payment_value=total))
    # review
    score = None
    if status == "delivered" and rnd.random() < .97:
        score = rnd.choices([1, 2, 3, 4, 5], SCORE_LATE if late else SCORE_ON)[0]
        created = delivered.normalize() + pd.Timedelta(days=rnd.randint(0, 4))
    elif status == "canceled" and rnd.random() < .3:
        score, created = 1, ts.normalize() + pd.Timedelta(days=rnd.randint(1, 6))
    if score is not None:
        msg = rnd.choice(PHRASES[score]) if rnd.random() < .4 else ""
        reviews.append(dict(review_id=hid("r", oc), order_id=oid, review_score=score,
                            review_comment_title=("" if rnd.random() < .88 else "Avaliação"),
                            review_comment_message=msg, review_creation_date=fmt(created),
                            review_answer_timestamp=fmt(created + pd.Timedelta(hours=rnd.uniform(5, 60)))))
    return status, delivered, late, score


for p in range(N_CUSTOMERS):
    uid = hid("cu", p)
    st = st_names[bisect.bisect(st_cum, rnd.random()) % len(st_names)]
    city, zp = city_for(st), zip5()
    ts = first_ts()
    while True:
        status, delivered, late, score = build_order(uid, st, city, zp, ts)
        if status != "delivered":
            break
        # ASSUMPTION (planted effect): repeat probability depends on the delivery/review experience
        if late: pr = 0.08
        elif score is not None and score <= 3: pr = 0.20
        else: pr = 0.30
        if rnd.random() > pr: break
        ts = delivered + pd.Timedelta(days=20 + rnd.gammavariate(2.0, 45.0), hours=rnd.randrange(24))
        if ts > END: break

orders = pd.DataFrame(orders); items = pd.DataFrame(items); pays = pd.DataFrame(pays)
reviews = pd.DataFrame(reviews); customers = pd.DataFrame(customers)

# --------------------------------------------- inject realistic data-quality issues
deliv_idx = orders.index[orders.order_status == "delivered"].to_numpy()
pick = nrng.choice(deliv_idx, 190, replace=False)
for i in pick[:70]:   # delivered BEFORE purchase
    pt = pd.Timestamp(orders.at[i, "order_purchase_timestamp"])
    orders.at[i, "order_delivered_customer_date"] = fmt(pt - pd.Timedelta(days=rnd.randint(1, 20)))
for i in pick[70:]:   # status delivered but no delivery date
    orders.at[i, "order_delivered_customer_date"] = ""
dup = reviews.sample(frac=0.012, random_state=1).copy()          # same review_id twice
dup["review_answer_timestamp"] = (pd.to_datetime(dup.review_answer_timestamp) + pd.Timedelta(days=2)).dt.strftime("%Y-%m-%d %H:%M:%S")
two = reviews.sample(frac=0.005, random_state=2).copy()          # 2nd review, same order
two["review_id"] = [hid("rx", i) for i in range(len(two))]
two["review_creation_date"] = (pd.to_datetime(two.review_creation_date) + pd.Timedelta(days=5)).dt.strftime("%Y-%m-%d %H:%M:%S")
two["review_answer_timestamp"] = (pd.to_datetime(two.review_answer_timestamp) + pd.Timedelta(days=5)).dt.strftime("%Y-%m-%d %H:%M:%S")
reviews = pd.concat([reviews, dup, two]).sample(frac=1, random_state=3).reset_index(drop=True)

translation = pd.DataFrame(CATS, columns=["product_category_name", "product_category_name_english"])
for name, df in [("customers", customers), ("orders", orders), ("order_items", items), ("order_payments", pays),
                 ("order_reviews", reviews), ("products", products), ("sellers", sellers),
                 ("product_category_name_translation", translation)]:
    df.to_csv(os.path.join(OUT, f"{name}.csv"), index=False)
    print(f"{name:36s}{len(df):>9,d} rows")
d = orders[orders.order_status == "delivered"]
print(f"unique customers {customers.customer_unique_id.nunique():,}; orders per customer "
      f"{len(orders) / customers.customer_unique_id.nunique():.2f}")
