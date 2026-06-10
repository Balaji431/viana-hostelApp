# 🏨 VStay - Hostel Management System

VStay is a modern, premium web application designed to manage hostel accommodations, bookings, capacity allocations, payments, and warden operations.

The application is built using a containerized, decoupled architecture:
*   **Frontend**: Flutter Web (compiled to optimized JS/WASM, served via Nginx)
*   **Backend**: PHP REST API (handling core operations, database queries, and notifications)
*   **Database**: MySQL (relational database with time-zone optimizations for IST)
*   **Containers**: Docker & Docker Compose (orchestrates frontend, backend, database, and phpMyAdmin)

---

## 💻 Software Prerequisites & Tooling

To run and edit this application on any machine (e.g., if you set up a new laptop), you need to install the following software:

### 1. Core Runtime (Recommended - runs the entire app in 1 click)
*   **Docker Desktop**: Configures, builds, and launches the entire stack inside containers.
    *   📥 [Download Docker Desktop](https://www.docker.com/products/docker-desktop/)

### 2. Manual Development & Compilation (Optional - if you want to modify Flutter code)
*   **Git**: Version control tool to clone code and push changes daily.
    *   📥 [Download Git](https://git-scm.com/)
*   **Flutter SDK**: Required to build the web frontend (`flutter build web`).
    *   📥 [Download Flutter SDK](https://docs.flutter.dev/get-started/install)
*   **XAMPP / PHP / Apache**: If you want to test the PHP backend files natively on Windows instead of in Docker.
    *   📥 [Download XAMPP](https://www.apachefriends.org/index.html)
*   **VS Code**: The recommended IDE for Dart, Flutter, and PHP development.
    *   📥 [Download VS Code](https://code.visualstudio.com/)

---

## 🛡️ Setup Guide: Recovering/Running the App from Scratch

If you are setting up this project on a brand new laptop, follow these exact steps to get up and running:

### Step 1: Clone the Code from GitHub
Open your terminal (PowerShell or Bash) and clone the repository:
```bash
git clone https://github.com/Balaji431/viana-hostelApp.git
cd viana-hostelApp
```

### Step 2: Restore the Git-Ignored Configs & Credentials
Since sensitive keys and configurations are git-ignored for safety, you need to recreate them:
1.  **Backend Secrets**: 
    *   Go to `hostel_backend/config/`.
    *   Copy `secrets.example.php` and rename it to `secrets.php`.
    *   Open `secrets.php` and input your database credentials and API keys.
2.  **Firebase Credentials**:
    *   Place your Firebase Service Account JSON private key in `hostel_backend/config/service-account.json`. (This is required for sending push notifications).
3.  **Local API Configuration** (If needed for local running):
    *   Ensure [`api_service.dart`](file:///c:/xampp/htdocs/hostelapp/lib/core/api_service.dart) and [`web/config.json`](file:///c:/xampp/htdocs/hostelapp/web/config.json) match your target backend URL (`http://localhost:8081/` for local, or your production VPS domain).

### Step 3: Restore the Database Data
Since raw database entries (user accounts, students, bookings) are not stored in Git, you need to import your database backup:
1.  Launch phpMyAdmin (via XAMPP or Docker) or connect to your local MySQL instance.
2.  Create a database named `stay_simats`.
3.  Import your latest SQL backup file (e.g., `schema.sql` or `stay_simats.sql`).

### Step 4: Run the Application

#### Option A: Running via Docker (Easiest & Consistent)
Launch all services (frontend, backend, database, phpMyAdmin) with a single command:
```bash
docker compose up -d --build
```
Once up, access the services:
*   🌐 **Frontend App**: `http://localhost:8080`
*   ⚙️ **Backend API**: `http://localhost:8081`
*   🔧 **phpMyAdmin**: `http://localhost:8082`

#### Option B: Development Mode (Hot Reload)
If you are actively coding:
1.  Start MySQL database locally on port 3307 or 3306.
2.  Start local Apache/PHP server serving `hostel_backend` folder on port 8081.
3.  Run the Flutter web app locally:
    ```bash
    flutter run -d chrome
    ```

---

## 🗄️ Credential & Database Backup Best Practices

To ensure you never lose any data or configuration files if your laptop is lost or damaged:

1.  **Backup `secrets.php` and `service-account.json`**:
    *   Keep a copy of these files in a secure cloud service (Google Drive, OneDrive, or a password manager like Bitwarden).
2.  **Regular Database Backups**:
    *   Run regular database exports from phpMyAdmin or via command line.
    *   Save your `.sql` backup files in a secure storage drive. Do NOT check them into public GitHub repositories.
3.  **Use Private Repositories**:
    *   Ensure your GitHub repository (`Balaji431/viana-hostelApp`) is set to **Private** so that your proprietary code structure remains confidential.

---

## 🔄 Daily Sync Workflow
Stay up to date by committing your changes at the end of each day:
```bash
git add .
git commit -m "Update: Added new features/fixes"
git push origin main
```
