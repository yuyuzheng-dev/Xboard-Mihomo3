# XBoard App Changes

This document outlines the recent changes made to the XBoard application.

## Offline White Screen Fix

**Problem:** The application would show a white screen if it was launched without an internet connection. This was due to the application hanging while trying to fetch the remote configuration.

**Solution:**

1.  **Initialization State:** A new state provider (`initializationProvider`) was created to manage the application's initialization state. The possible states are `initializing`, `success`, and `error`.
2.  **Error Handling:** The main application entry point (`main.dart`) was modified to handle initialization errors gracefully.
3.  **User Interface:**
    *   A **splash screen** is now displayed while the application is initializing.
    *   If an error occurs during initialization (e.g., no network connection), an **error screen** is displayed with a "Reload" button.
    *   The main application is only shown after a successful initialization.

## Announcement Button Enhancement

**Problem:** The announcement button in the VPN panel did not re-fetch the announcement data when clicked. This meant that users would not see new announcements until they restarted the application.

**Solution:**

1.  **Data Refresh:** The `onTap` callback for the announcement button was modified to always fetch the latest announcements from the server.
2.  **User Feedback:**
    *   If there are no announcements, a `SnackBar` is displayed with the message "暂无公告" (No announcements).
    *   If there are announcements, the announcement details are displayed in a bottom sheet as before.
