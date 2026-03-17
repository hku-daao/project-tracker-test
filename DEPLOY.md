# Deploy to Firebase Hosting

Your app is configured to deploy to:
- **Project ID:** daao-a20c6  
- **URL:** https://testprojectmanagementtracking.firebaseapp.com/

## One-time setup

### 1. Install Firebase CLI

**Option A – Using Node.js (if you install Node.js):**
```powershell
npm install -g firebase-tools
```

**Option B – Standalone (no Node.js):**  
Download the Firebase CLI binary for Windows from:  
https://firebase.google.com/docs/cli#install_the_firebase_cli  
Then add the folder containing `firebase.exe` to your PATH.

### 2. Log in to Firebase
```powershell
firebase login
```
Sign in with the Google account that owns project **daao-a20c6**.

## Deploy

From the project root, run:

```powershell
# 1. Build the Flutter web app
flutter build web

# 2. Deploy to Firebase Hosting
firebase deploy
```

After a successful deploy, the site will be at:
**https://testprojectmanagementtracking.firebaseapp.com/**

To deploy only hosting (skip other Firebase services):
```powershell
firebase deploy --only hosting
```
