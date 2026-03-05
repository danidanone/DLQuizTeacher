# Project Overview

This document outlines the setup and configuration of the DL-mini-Kahoot Firebase project.

## Authentication Setup

To enable Firebase authentication for the Android apps, the following steps were taken:

1.  **Retrieved SHA Fingerprints:** The SHA-1 and SHA-256 fingerprints were retrieved from the Android debug keystore.
2.  **Associated Fingerprints with Firebase Apps:** The retrieved SHA fingerprints were added to the following Android apps in the Firebase project:
    *   `DL Mini Kahoot Teacher`
    *   `Mini Kahoot StudentDL`
    *   `minikahootdl_student (android)`
    *   `myapp (android)`

This ensures that the Android apps are properly authenticated with Firebase.
