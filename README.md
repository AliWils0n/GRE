# Wilson GRE

مدیریت تعاملی GRE روی IPv4 برای اتصال دو سرور **IRAN ↔ FOREIGN** و انتقال پورت‌های ایران به سرویس‌های روی سرور خارج. یک فایل Bash مستقل، بدون Python در زمان اجرا. **برای اجرا فقط `gre.sh` لازم است**؛ فایل‌های دیگر راهنما و تست‌اند. گزینهٔ `1 — Setup + auto boot` تنظیمات را ذخیره، نسخهٔ مستقل را نصب و سرویس شروع خودکار را فعال می‌کند. پس از reboot به اجرای دوباره، دانلود GitHub یا ورود دوبارهٔ کانفیگ نیازی نیست.

> وضعیت تحویل: نحو Bash، ShellCheck و ۴۳ تست محلی قواعد/ورودی‌ها بررسی شده‌اند. تست واقعی لینوکس در `tests/integration.py` و GitHub Actions آماده است، اما در محیط ویندوز سازنده اجرا نشده است. پیش از استفاده روی سرور اصلی، سبزشدن CI و تست دو سرور آزمایشی را بررسی کنید. هیچ ادعای «بدون باگ» یا تضمین کاهش پینگ وجود ندارد.

## راه‌اندازی سریع

۱. محتوای این پوشه را در ریشهٔ یک repository، مثلاً `wilson-gre`، قرار دهید؛ فایل `gre.sh` باید در ریشه باشد. نیازی به ویرایش نام پروژه یا URL داخل کد برای اجرای منو نیست.

۲. روی هر دو سرور لینوکسی، وابستگی‌ها را نصب کنید. نمونهٔ Debian/Ubuntu:

```bash
sudo apt-get update
sudo apt-get install -y bash curl iproute2 iptables conntrack iputils-ping util-linux procps coreutils
sudo -i
bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/wilson-gre/main/gre.sh)
```

`YOUR_USERNAME` و نام repository را جایگزین کنید. این فرمان از داخل Bash اجرا می‌شود؛ از `sudo bash <(...)` استفاده نکنید، چون دسترسی به descriptor بین کاربران می‌تواند مشکل داشته باشد. ابتدا `sudo -i` بزنید. برای استفادهٔ ثابت، به‌جای `main`، شناسهٔ کامل commit بررسی‌شده را در URL بگذارید.

در فرمان process substitution، شکست `curl` ممکن است به Bash خالی با کد موفق منتهی شود. مسیر دانلود قابل‌بررسی:

```bash
curl -fSL https://raw.githubusercontent.com/YOUR_USERNAME/wilson-gre/COMMIT_SHA/gre.sh -o gre.sh &&
  bash -n gre.sh && sudo bash gre.sh
```

۳. روی سرورهای دارای systemd، ابتدا خارج و سپس ایران را با گزینهٔ **`1 — Setup + auto boot`** راه‌اندازی کنید. هر سرور فقط بار اول اطلاعات زیر را می‌پرسد؛ گزینهٔ ۹ برای configure بدون نصب خودکار است:

| گزینه | ایران | خارج |
|---|---|---|
| Role | IRAN | FOREIGN |
| Local outer IPv4 | IP خود ایران | IP خود خارج |
| Peer outer IPv4 | IP خارج | IP ایران |
| WAN | رابط مسیر peer و ورود کاربران | رابط مسیر peer |
| GRE network | `10.200.200.0/30` | همان شبکه |
| IP خودکار تونل | `10.200.200.2` | `10.200.200.1` |
| Mode، پورت‌ها، MTU | انتخاب شما | همان مقادیر |
| Management | تمام پورت‌های مدیریت، شامل 22 | تمام پورت‌های مدیریت، شامل 22 |

شبکهٔ /30 باید خصوصی و روی هر دو میزبان بدون تداخل با routeهای موجود باشد. IPهای `192.0.2.x` در فایل‌های نمونه صرفاً نمونه‌اند؛ با IP واقعی جایگزین شوند. interface ممکن است `ens3` یا `enp1s0` باشد؛ نام واقعی را وارد کنید.

لیست پورت‌ها باید یکتا، صعودی و جداشده با ویرگول باشد، مثل `22,443,8443`. برای هیچ پورتی `-` وارد کنید. هر لیست حداکثر ۱۲۸ پورت دارد؛ بازه‌ها پشتیبانی نمی‌شوند. پورت‌های مدیریت بر انتخاب پورت‌های forwarding اولویت دارند و برای **TCP و UDP** مستثنا هستند. پورت SSH جاری و پورت‌های گزارش‌شده توسط `sshd -T` نیز هنگام شروع کنترل می‌شوند؛ پورت‌های پنل، SSH socket activation و سرویس‌های مدیریتی سفارشی را خودتان اضافه کنید.

۴. روی ایران باید `net.ipv4.ip_forward=1` در سیاست سیستم فعال باشد. اسکریپت خودکار این تنظیم سراسری را عوض نمی‌کند: تغییر آن می‌تواند تنظیمات دیگر هسته را به پیش‌فرض برگرداند و با Docker یا مسیریابی میزبان تداخل کند. اگر غیرفعال است، از کنسول سرور و با بررسی تنظیمات فعلی فعالش کنید؛ برای نمونه:

```bash
sudo sysctl -w net.ipv4.ip_forward=1
```

برای ماندگاری، `net.ipv4.ip_forward=1` را در تنظیمات sysctl تحت مدیریت خودتان قرار دهید؛ تنظیمات سفارشی host/router را پس از تغییر بازبینی کنید. ابزار هنگام توقف این تنظیم مشترک را به صفر برنمی‌گرداند.

۵. سرویس مقصد باید روی IP تونل خارج یا `0.0.0.0` و همان پورت گوش کند. اتصال فقط به `127.0.0.1` یا فقط IP عمومی خارج کافی نیست. این نسخه proxy برای کانتینر یا forwarding به سرور سوم نیست؛ در صورت نیاز از listener میزبان استفاده کنید.

## منو و فرمان‌ها

| فرمان | کار |
|---|---|
| `setup` | تنظیم اولیه، نصب و فعال‌سازی boot و شروع سرویس؛ گزینهٔ ۱ منو |
| `configure` | تنظیم تعاملی؛ فقط در حالت متوقف |
| `start` | پیش‌بررسی، ساخت تونل و قوانین؛ اجرای مجدد بدون قانون تکراری |
| `stop` | توقف تونل، حذف قوانین متعلق به پروژه و NAT connectionهای همان relay |
| `restart` | توقف و شروع مجدد با تنظیم فعلی؛ اتصال‌های فعال قطع می‌شوند |
| `status` | وضعیت و بررسی وجود/تغییر قواعد اختصاصی، آمار interface |
| `diagnostics` | route، counters فایروال، ping و probe اندازهٔ MTU |
| `install-service` | نصب نسخهٔ محلی و فعال‌سازی شروع در boot |
| `uninstall-service` | توقف، حذف service و فایل نصب‌شده؛ حفظ config و log |
| `--version` | نسخه بدون نیاز به root |

```bash
bash gre.sh configure
bash gre.sh start
bash gre.sh diagnostics
bash gre.sh stop
```

نصب حتی هنگام اجرای `bash <(curl ...)` به فایل جانبی یا دانلود دوم نیاز ندارد: کد بارگذاری‌شده در تابع اصلی با builtin خود Bash به یک اسکریپت مستقل تبدیل و پس از بررسی syntax ذخیره می‌شود. در نتیجه نسخهٔ نصب‌شده همان کد اجراشده است؛ از `eval` استفاده نمی‌شود. فرمت/کامنت‌های فایل نصب‌شده ممکن است متفاوت باشند. در boot فقط نسخهٔ محلی اجرا می‌شود.

گزینهٔ **Setup** هم نصب می‌کند و هم تونل را شروع می‌کند. فرمان جداگانهٔ `install-service` فقط نصب و boot را فعال می‌کند. وقتی سرویس نصب است، Start/Stop/Restart منو و فرمان‌های اسکریپت خودکار از systemd استفاده می‌کنند. فرمان‌های معادل:

```bash
sudo systemctl start wilson-gre
sudo systemctl status wilson-gre
sudo systemctl restart wilson-gre
sudo systemctl stop wilson-gre
sudo /usr/local/sbin/wilson-gre configure
sudo systemctl start wilson-gre
```

توقف عادی service، فعال‌بودن آن برای boot بعدی را حذف نمی‌کند. برای حذف شروع خودکار از `uninstall-service` استفاده کنید؛ config باقی می‌ماند. برای نصب نسخهٔ تازه، ابتدا service قبلی را uninstall و سپس از نسخهٔ تازه `install-service` و `start` اجرا کنید؛ نیازی به configure دوباره نیست.

## مسیر ترافیک و فایروال

```text
Client → IRAN_PUBLIC:selected_port
           DNAT → FOREIGN_GRE:same_port
           SNAT → IRAN_GRE
           GRE over IPv4 / protocol 47
         → local service on FOREIGN
Reply  ← conntrack reverses both translations
```

SNAT فقط برای اتصال DNAT‌شده به IP تونل خارج، در خروجی interface پروژه، اعمال می‌شود. سرور خارج IP تونل ایران را به‌عنوان آدرس client می‌بیند؛ حفظ IP واقعی client نیازمند طراحی دیگری با policy routing است و در این نسخه انجام نمی‌شود. هیچ default route تغییر نمی‌کند.

- `ports`: فقط TCP/UDP پورت‌های انتخابی؛ پیش‌فرض 443.
- `all`: همهٔ پورت‌های TCP/UDP به‌جز مدیریت؛ در منو نیازمند تایپ `ALL`. این حالت IP protocolهای دیگر از جمله ICMP و GRE را DNAT نمی‌کند.
- هیچ flush سراسری، تغییر policy یا تغییر chain متعلق به ابزار دیگر وجود ندارد. `-F` فقط برای chainهای اختصاصی ثبت‌شده در journal، بعد از جداشدن hookهایشان، استفاده می‌شود.
- زنجیره‌ها: `WG_GUARD`، `WG_TRANSIT`، `WG_INPUT`، `WG_FORWARD`، `WG_DNAT`، `WG_SNAT` و `WG_MSS`. نام‌ها و interface `wilson-gre` رزرو هستند؛ تنها یک تونل مدیریت می‌شود.
- guard ابتدای INPUT فقط GRE با peer/interface نامعتبر و inner address نامعتبر را drop می‌کند. guard ابتدای FORWARD فقط transit غیرمجاز interface خود پروژه را می‌بندد. این دو guard اجازهٔ عبور زودهنگام نمی‌دهند.
- hookهای ACCEPT و NAT انتهای chainهای اصلی اضافه می‌شوند. DROP/REJECT قبلی UFW/Fail2Ban همچنان مؤثر است. default policy=DROP بعد از قواعد ارزیابی می‌شود و مانع ACCEPT معتبر نیست.
- GRE بیرونی فقط از IP peer روی WAN برای IP محلی اجازه می‌گیرد. این فیلتر همهٔ GREهای دیگر به همان IP محلی را نیز می‌بندد؛ اگر آن IP برای تونل GRE دیگری استفاده می‌شود، این ابزار برای آن میزبان مناسب نیست.
- DNAT از LAN/loopback یا IP عمومی دیگر انجام نمی‌شود. UDP نیز همان مسیر NAT محدود را دارد. ارتباط ICMP عمومی توسط ابزار مسدود نمی‌شود؛ ICMP داخل تونل از peer مجاز است.

**همزیستی با فایروال به معنای تضمین عبور در هر تنظیمی نیست.** اگر UFW یک DROP/REJECT صریح زودتر دارد، باید اجازهٔ دقیق GRE از peer و forwarding انتخابی را در خود UFW تنظیم کنید. ابزار برای عبور دادن ترافیک سیاست آن را دور نمی‌زند. قوانین nftables مستقل، cloud firewall، OUTPUT DROP، policy routing و Fail2Ban نیز ممکن است عبور را محدود کنند. Docker اگر قبلاً همان پورت را DNAT کند اولویت دارد؛ پورت‌های مشترک را انتخاب نکنید. reload فایروال می‌تواند hookها را حذف یا ترتیبشان را عوض کند؛ diagnostics و سپس restart اجرا کنید. سرویس فقط بعد از سرویس‌های ذکرشده در boot ترتیب می‌گیرد و reload آینده را مانیتور نمی‌کند.

GRE **پروتکل IP شمارهٔ 47** است، نه TCP/UDP port 47. provider و فایروال بیرونی باید این پروتکل را در هر دو جهت عبور دهند. endpointهای این نسخه باید IP محلیِ قابل‌دسترسی از peer داشته باشند؛ NAT traversal خودکار، IPv6 و GRE داخل UDP پشتیبانی نمی‌شوند.

## امنیت، rollback و محدودهٔ تضمین

- GRE رمزنگاری، احراز هویت و محافظت رمزنگاری‌شده از داده ندارد. allowlist آدرس peer مانع جعل IP در شبکه‌ای که spoofing را اجازه می‌دهد نیست. برای محرمانگی از یک لایهٔ رمزنگاری مناسب استفاده کنید و سربار آن را حساب کنید.
- فایل تنظیمات `KEY=value` به‌صورت داده خوانده می‌شود؛ هیچ `source` یا `eval` روی آن انجام نمی‌شود. IP، شبکه، interface، پورت و MTU اعتبارسنجی می‌شوند.
- قفل `flock` اجرای همزمان خود ابزار را می‌بندد. تغییرات concurrent توسط مدیر دیگر فایروال یا مهاجم دارای root خارج از تضمین‌اند.
- journal ریشه‌محور و محدود به همین منابع، قبل از هر mutation ثبت می‌شود. خطا یا SIGINT/SIGTERM هنگام start باعث rollback hookها/chainها/interface خود ابزار می‌شود؛ snapshot کل فایروال restore نمی‌شود.
- اگر cleanup شکست بخورد، journal حفظ می‌شود؛ مشکل را رفع کرده و `stop` را دوباره اجرا کنید. SIGKILL قابل trap نیست؛ اجرای بعدی start وجود journal ناقص را گزارش می‌کند. پس از reboot منابع موقت شبکه و `/run` از نو ساخته می‌شوند.
- rollback به حالت **متوقف قبل از start** برمی‌گردد. restart اتصال‌ها را قطع می‌کند و اگر راه‌اندازی جدید شکست بخورد، تونل متوقف می‌ماند؛ rollback تضمین حفظ اتصال زنده نیست.
- stop ابتدا interface را down می‌کند؛ سپس منابع خود را حذف می‌کند. فقط conntrackهای TCP/UDP با original destination ایران و reply source/destination دو IP تونل حذف می‌شوند؛ conntrack کل سرور flush نمی‌شود. این کار مانع برگشت NAT قدیمی پس از تغییر پورت‌ها می‌شود.
- نصب service در خطا فایل‌های تازهٔ خودش را پس می‌گیرد. فایل/chain/interface موجود بدون مالکیت مشخص را تصاحب نمی‌کند. تغییر موفق configure ذخیره می‌شود؛ start ناموفق آن را به config قبلی برنمی‌گرداند.

## MTU، سرعت و پینگ

GRE پایه روی IPv4 حداقل **۲۴ بایت سربار برای هر بسته** دارد: ۲۰ بایت هدر IPv4 بیرونی + ۴ بایت GRE، بدون option/key/checksum/sequence. بنابراین «zero overhead» یا انتقال ۱:۱ در لایهٔ شبکه ممکن نیست؛ payload برنامه بدون تغییر عبور می‌کند، ولی تعداد بایت‌های شبکه بیشتر می‌شود. سربار لینک و VPN جداست.

برای مسیر با MTU برابر 1500، MTU داخلی 1476 مناسب است؛ این عدد برای همهٔ مسیرها درست نیست. اگر مسیر مؤثر VPN شما 1400 باشد، مقدار اولیهٔ GRE باید حداکثر 1376 باشد. سقف این ابزار 1476 است و jumbo frame تنظیم نمی‌کند. مسیر رفت و برگشت و هر دو peer را بررسی کنید.

PMTUD فعال می‌ماند. MSS در SYN و SYN-ACK با سقف `MTU - 40` برای IPv4/TCP و clamp به PMTU محدود می‌شود؛ فقط MSSهای بزرگ کاهش می‌یابند. MSS برای UDP کاربرد ندارد؛ اندازهٔ datagram برنامه را با MTU هماهنگ کنید. مسدودشدن پیام ICMP fragmentation-needed در هر لایه می‌تواند باعث black hole شود؛ اسکریپت آن را drop نمی‌کند اما نمی‌تواند فایروال provider را اصلاح کند.

GRE خودش TCP wrapper، retransmission یا head-of-line blocking نوع TCP اضافه نمی‌کند. **اگر VPN بالادستی TCP باشد، سربار TCP و head-of-line blocking همان VPN همچنان وجود دارند**؛ GRE آن را حذف نمی‌کند و TCP-over-TCP احتمالی باقی می‌ماند. encapsulation کمتر به‌تنهایی مسیر فیزیکی یا latency را بهتر نمی‌کند. بهبود احتمالی تابع routing، ازدحام، loss، CPU، ظرفیت و سیاست provider است. قبل/بعد را از سمت کاربر و در ساعت مشابه، با ping و تست کاربرد واقعی مقایسه کنید. این نسخه sysctlهای عمومی، congestion control، queue، offload یا socket buffer میزبان را «تیون» نمی‌کند.

مراجع فنی: [GRE — RFC 2784](https://datatracker.ietf.org/doc/html/rfc2784)، [ip-tunnel](https://man7.org/linux/man-pages/man8/ip-tunnel.8.html)، [TCPMSS و conntrack](https://man7.org/linux/man-pages/man8/iptables-extensions.8.html)، [رفتار ip_forward در هسته](https://docs.kernel.org/networking/ip-sysctl.html).

## فایل‌ها و عیب‌یابی

```text
/etc/wilson-gre/config              تنظیمات؛ دسترسی محدود به root
/run/wilson-gre/                    lock، journal، config فعال و rules
/var/log/wilson-gre.log             رویدادها و stderr؛ حاوی IPها
/usr/local/sbin/wilson-gre          پس از نصب service
/etc/systemd/system/wilson-gre.service
```

برای log rotation می‌توانید الگوی `examples/wilson-gre.logrotate` را پس از بررسی در `/etc/logrotate.d/wilson-gre` قرار دهید؛ ابزار خودکار فایل‌های logrotate را تغییر نمی‌دهد.

```bash
sudo /usr/local/sbin/wilson-gre diagnostics
sudo tail -n 100 /var/log/wilson-gre.log
sudo journalctl -u wilson-gre -n 100 --no-pager
sudo ss -lntup
```

اول تطابق IPها و route peer، سپس مجازبودن GRE، counters فایروال، listener خارج و MTU را بررسی کنید. سبز بودن status به معنای دسترسی end-to-end نیست. اگر config هنگام running دستی تغییر کرده باشد، start از ادامه جلوگیری می‌کند؛ ابتدا stop سپس start.

## توسعه و تست

```bash
bash -n gre.sh
shellcheck -S warning gre.sh
bash tests/unit.sh ./gre.sh
bash tests/self_install.sh ./gre.sh /tmp/wilson-gre-serialized.sh
mkdir -p /tmp/wilson-gre-rollback
bash tests/rollback.sh ./gre.sh /tmp/wilson-gre-rollback
# فقط روی Linux VM آزمایشی با root و امکان network namespace:
sudo python3 tests/integration.py
```

تست یکپارچه چهار network namespace می‌سازد و فایروال و sysctl میزبان اصلی را تغییر نمی‌دهد. TCP/UDP واقعی، ping/MTU، عدم تکرار، احترام به DROP موجود، حالت all، stop و تزریق خطا در آخرین hook را می‌آزماید. GitHub Actions آن را با `iptables-nft` و `iptables-legacy` اجرا می‌کند. وجود CI فایل به معنای اجرا یا پاس‌شدن آن در این تحویل نیست. UFW/Docker/Fail2Ban واقعی و providerهای ایران نیازمند تست محیط خودتان هستند.

ساختار repository:

```text
gre.sh
README.md
SECURITY.md
LICENSE
VALIDATION.md
examples/
tests/
.github/workflows/test.yml
.gitattributes
.gitignore
```
