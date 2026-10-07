# 🚀 اسکریپت GRE Tunnel

اسکریپتی ساده و کاربردی برای راه‌اندازی و مدیریت **GRE Tunnel** روی سرورهای لینوکسی.

هدف این پروژه، ساده‌تر کردن مراحل راه‌اندازی GRE و کاهش تنظیمات دستی است تا بتوانید با چند مرحله، تنظیمات موردنیاز را روی سرور انجام دهید.

---

## ⚡ نصب سریع

برای اجرای اسکریپت، دستور زیر را روی سرور وارد کنید:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/AliWils0n/GRE/main/gre.sh)
```

---

## 📋 پیش‌نیازها

قبل از اجرای اسکریپت، موارد زیر را بررسی کنید:

- سیستم‌عامل Linux
- دسترسی `root` یا `sudo`
- نصب بودن `bash`
- نصب بودن `curl`
- اتصال فعال اینترنت

برای بررسی نصب بودن `curl`:

```bash
curl --version
```

در صورت نیاز ابتدا وارد محیط Root شوید:

```bash
sudo -i
```

---

## 🛠 نحوه استفاده

ابتدا از طریق SSH وارد سرور شوید و سپس دستور زیر را اجرا کنید:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/AliWils0n/GRE/main/gre.sh)
```

پس از اجرا، مراحل و گزینه‌های موجود در اسکریپت نمایش داده می‌شوند و می‌توانید تنظیمات موردنظر را انجام دهید.

---

## 📥 نصب به‌صورت دستی

اگر ترجیح می‌دهید قبل از اجرا سورس اسکریپت را بررسی کنید:

```bash
git clone https://github.com/AliWils0n/GRE.git
cd GRE
chmod +x gre.sh
./gre.sh
```

استفاده از این روش مخصوصاً روی سرورهای Production توصیه می‌شود، چون می‌توانید کد را قبل از اجرا بررسی کنید.

---

## 🔄 دریافت آخرین نسخه

برای اجرای آخرین نسخه موجود در مخزن، کافی است دوباره دستور زیر را اجرا کنید:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/AliWils0n/GRE/main/gre.sh)
```

---

## 🔐 نکات امنیتی

اجرای مستقیم اسکریپت‌های اینترنتی با `curl` سریع و راحت است، اما توصیه می‌شود قبل از اجرای هر اسکریپت با دسترسی Root، سورس آن را بررسی کنید.

تمام کدهای این پروژه در همین Repository قابل مشاهده هستند.

---

## 🔧 رفع مشکلات

اگر اسکریپت اجرا نشد، ابتدا وجود `curl` را بررسی کنید:

```bash
curl --version
```

سپس مطمئن شوید دسترسی Root دارید:

```bash
whoami
```

در صورت نیاز:

```bash
sudo -i
```

و مجدداً اسکریپت را اجرا کنید.

---

## 🗑 حذف تنظیمات

اگر نسخه فعلی اسکریپت دارای گزینه حذف یا `Uninstall` است، از همان گزینه برای حذف تنظیمات ایجادشده استفاده کنید.

در غیر این صورت، قبل از حذف دستی تنظیمات، تغییراتی که اسکریپت روی سیستم ایجاد کرده است را بررسی کنید.

---

## 🤝 مشارکت در پروژه

پیشنهادها، گزارش مشکلات و مشارکت در توسعه پروژه استقبال می‌شوند.

برای گزارش مشکل می‌توانید یک **Issue** ایجاد کنید و برای مشارکت در توسعه پروژه **Pull Request** ارسال کنید.

---

## ⚠️ مسئولیت استفاده

این پروژه بدون هیچ‌گونه ضمانت ارائه می‌شود.

مسئولیت بررسی کد، نحوه استفاده و تغییراتی که اسکریپت روی سرور ایجاد می‌کند بر عهده کاربر است.

---

## 📜 License

مجوز موردنظر پروژه را می‌توانید در فایل `LICENSE` قرار دهید.

---

## ⭐ اجرای سریع

```bash
bash <(curl -sSL https://raw.githubusercontent.com/AliWils0n/GRE/main/gre.sh)
```

اگر پروژه برایتان مفید بود، با دادن ⭐ به Repository از توسعه آن حمایت کنید.



# GRE Script

A lightweight Bash script designed to simplify GRE-related setup and configuration on Linux servers.

The project focuses on providing a fast, straightforward installation process with minimal manual configuration.

## Quick Installation

Run the following command on your server:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/AliWils0n/GRE/main/gre.sh)
```

## Requirements

Before running the script, make sure your server has:

- A Linux-based operating system
- Root or `sudo` privileges
- `bash`
- `curl`
- An active internet connection

## Usage

Connect to your server via SSH and execute:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/AliWils0n/GRE/main/gre.sh)
```

The script will start automatically. Follow the on-screen instructions to complete the configuration.

## Manual Installation

If you prefer to inspect the script before executing it:

```bash
git clone https://github.com/AliWils0n/GRE.git
cd GRE
chmod +x gre.sh
./gre.sh
```

This method is recommended if you want to review the source code before running it with root privileges.

## Update

To use the latest version, simply run the installation command again:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/AliWils0n/GRE/main/gre.sh)
```

## Security

Running remote scripts directly with `curl | bash` or process substitution is convenient, but you should always review the source code before executing it on a production server.

You can inspect the script in this repository before installation.

## Supported Systems

Compatibility depends on the current implementation of `gre.sh`. Check the script and repository updates for the latest supported distributions and versions.

## Troubleshooting

If the script does not start, verify that `curl` is installed:

```bash
curl --version
```

Also make sure you are running the script with sufficient privileges.

If necessary:

```bash
sudo -i
```

Then run the installation command again.

## Uninstall

If the project provides an uninstall option, use the corresponding option from the script menu. Otherwise, review the changes performed by `gre.sh` before manually removing the configuration.

## Contributing

Contributions, bug reports, and improvements are welcome.

Feel free to open an Issue or submit a Pull Request.

## Disclaimer

This project is provided as-is, without warranty. You are responsible for reviewing the script and understanding the changes it makes to your system before using it, especially on production servers.

## License

Add the appropriate license for this project in the `LICENSE` file.

---

### One-Line Install

```bash
bash <(curl -sSL https://raw.githubusercontent.com/AliWils0n/GRE/main/gre.sh)
```
