// Skip the "leaving/entering full screen" warning delay and animation.
user_pref("full-screen-api.warning.timeout", 0);
user_pref("full-screen-api.transition-duration.enter", "0 0");
user_pref("full-screen-api.transition-duration.leave", "0 0");

// Show the full URL in the address bar instead of trimming "https://" and "www.".
user_pref("browser.urlbar.trimURLs", false);

// Block autoplay for media with sound (2 = block audible autoplay).
user_pref("media.autoplay.default", 2);

// Enable tracking protection, including social media trackers.
user_pref("privacy.trackingprotection.enabled", true);
user_pref("privacy.trackingprotection.socialtracking.enabled", true);
