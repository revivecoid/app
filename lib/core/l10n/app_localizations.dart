import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_id.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppL
/// returned by `AppL.of(context)`.
///
/// Applications need to include `AppL.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppL.localizationsDelegates,
///   supportedLocales: AppL.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppL.supportedLocales
/// property.
abstract class AppL {
  AppL(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppL? of(BuildContext context) {
    return Localizations.of<AppL>(context, AppL);
  }

  static const LocalizationsDelegate<AppL> delegate = _AppLDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('id')
  ];

  /// Application name
  ///
  /// In en, this message translates to:
  /// **'Revive'**
  String get appName;

  /// No description provided for @appTagline.
  ///
  /// In en, this message translates to:
  /// **'Automotive Body Repair Portal'**
  String get appTagline;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get saveChanges;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @submit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submit;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @or.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get or;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @filter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filter;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @seeAll.
  ///
  /// In en, this message translates to:
  /// **'See All'**
  String get seeAll;

  /// No description provided for @optional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optional;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @success.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get success;

  /// No description provided for @warning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get warning;

  /// No description provided for @info.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get info;

  /// No description provided for @noDataFound.
  ///
  /// In en, this message translates to:
  /// **'No data found.'**
  String get noDataFound;

  /// No description provided for @somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get somethingWentWrong;

  /// No description provided for @networkError.
  ///
  /// In en, this message translates to:
  /// **'Network error. Check your connection.'**
  String get networkError;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @darkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark Mode'**
  String get darkMode;

  /// No description provided for @lightMode.
  ///
  /// In en, this message translates to:
  /// **'Light Mode'**
  String get lightMode;

  /// No description provided for @systemDefault.
  ///
  /// In en, this message translates to:
  /// **'System Default'**
  String get systemDefault;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Log Out'**
  String get logout;

  /// No description provided for @logoutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to log out?'**
  String get logoutConfirm;

  /// No description provided for @languageId.
  ///
  /// In en, this message translates to:
  /// **'Bahasa Indonesia'**
  String get languageId;

  /// No description provided for @languageEn.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEn;

  /// No description provided for @heroTagBadge.
  ///
  /// In en, this message translates to:
  /// **'AUTOMOTIVE AI CARE'**
  String get heroTagBadge;

  /// No description provided for @heroTitle.
  ///
  /// In en, this message translates to:
  /// **'Body Repair\nMade Simple.'**
  String get heroTitle;

  /// No description provided for @heroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Instant body repair estimation & real-time tracking. Get your car shining faster, with absolute transparency.'**
  String get heroSubtitle;

  /// No description provided for @heroCtaButton.
  ///
  /// In en, this message translates to:
  /// **'Get Free AI Estimate'**
  String get heroCtaButton;

  /// No description provided for @contactUs.
  ///
  /// In en, this message translates to:
  /// **'CONTACT US'**
  String get contactUs;

  /// No description provided for @activeRepair.
  ///
  /// In en, this message translates to:
  /// **'ACTIVE REPAIR'**
  String get activeRepair;

  /// No description provided for @repairProgress.
  ///
  /// In en, this message translates to:
  /// **'Repair Progress'**
  String get repairProgress;

  /// No description provided for @inProgress.
  ///
  /// In en, this message translates to:
  /// **'In Progress'**
  String get inProgress;

  /// No description provided for @pending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pending;

  /// No description provided for @trackLive.
  ///
  /// In en, this message translates to:
  /// **'Track Live'**
  String get trackLive;

  /// No description provided for @newClaim.
  ///
  /// In en, this message translates to:
  /// **'New Claim'**
  String get newClaim;

  /// No description provided for @newClaimDesc.
  ///
  /// In en, this message translates to:
  /// **'Scan car damage with AI'**
  String get newClaimDesc;

  /// No description provided for @startScan.
  ///
  /// In en, this message translates to:
  /// **'Start Scan'**
  String get startScan;

  /// No description provided for @trackStatus.
  ///
  /// In en, this message translates to:
  /// **'Track Status'**
  String get trackStatus;

  /// No description provided for @trackStatusDesc.
  ///
  /// In en, this message translates to:
  /// **'Live workshop cameras'**
  String get trackStatusDesc;

  /// No description provided for @viewQueue.
  ///
  /// In en, this message translates to:
  /// **'View Queue'**
  String get viewQueue;

  /// No description provided for @aiTelemetryHub.
  ///
  /// In en, this message translates to:
  /// **'AI TELEMETRY HUB'**
  String get aiTelemetryHub;

  /// No description provided for @slaLabel.
  ///
  /// In en, this message translates to:
  /// **'SLA < 48 Hrs'**
  String get slaLabel;

  /// No description provided for @networkTitle.
  ///
  /// In en, this message translates to:
  /// **'Jabodetabek Certified Network'**
  String get networkTitle;

  /// No description provided for @networkDesc.
  ///
  /// In en, this message translates to:
  /// **'Over 38 OEM-compliant spray booths with digitized color-matching precision down to 99.4% factory accuracy.'**
  String get networkDesc;

  /// No description provided for @seamlessProcess.
  ///
  /// In en, this message translates to:
  /// **'SEAMLESS PROCESS'**
  String get seamlessProcess;

  /// No description provided for @howItWorks.
  ///
  /// In en, this message translates to:
  /// **'How It Works'**
  String get howItWorks;

  /// No description provided for @step1Title.
  ///
  /// In en, this message translates to:
  /// **'Snap Damage Photos'**
  String get step1Title;

  /// No description provided for @step1Desc.
  ///
  /// In en, this message translates to:
  /// **'Take 3 clear photos around your vehicle dents, scratches, or panel gaps directly in the web scanner.'**
  String get step1Desc;

  /// No description provided for @step2Title.
  ///
  /// In en, this message translates to:
  /// **'Instant AI Assessment'**
  String get step2Title;

  /// No description provided for @step2Desc.
  ///
  /// In en, this message translates to:
  /// **'Get sub-millimeter part analysis and guaranteed fixed-price estimate with parts catalog breakdown.'**
  String get step2Desc;

  /// No description provided for @step3Title.
  ///
  /// In en, this message translates to:
  /// **'Select Hub & Bay'**
  String get step3Title;

  /// No description provided for @step3Desc.
  ///
  /// In en, this message translates to:
  /// **'Choose your closest certified workshop and lock priority slot reservation with door-to-door towing.'**
  String get step3Desc;

  /// No description provided for @step4Title.
  ///
  /// In en, this message translates to:
  /// **'Live Tracking to Handover'**
  String get step4Title;

  /// No description provided for @step4Desc.
  ///
  /// In en, this message translates to:
  /// **'Watch real-time prep, booth painting, and quality control telemetry until delivery back to your driveway.'**
  String get step4Desc;

  /// No description provided for @recentInspections.
  ///
  /// In en, this message translates to:
  /// **'RECENT INSPECTIONS'**
  String get recentInspections;

  /// No description provided for @trustVerified.
  ///
  /// In en, this message translates to:
  /// **'TRUST & VERIFIED'**
  String get trustVerified;

  /// No description provided for @trustTitle.
  ///
  /// In en, this message translates to:
  /// **'Why Revive?'**
  String get trustTitle;

  /// No description provided for @quickLinks.
  ///
  /// In en, this message translates to:
  /// **'QUICK LINKS'**
  String get quickLinks;

  /// No description provided for @linkFaq.
  ///
  /// In en, this message translates to:
  /// **'FAQ & Help'**
  String get linkFaq;

  /// No description provided for @linkAbout.
  ///
  /// In en, this message translates to:
  /// **'About Revive'**
  String get linkAbout;

  /// No description provided for @linkPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get linkPrivacy;

  /// No description provided for @linkSupport.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get linkSupport;

  /// No description provided for @footerCopyright.
  ///
  /// In en, this message translates to:
  /// **'© 2025 Revive Technologies Indonesia'**
  String get footerCopyright;

  /// No description provided for @footerTagline.
  ///
  /// In en, this message translates to:
  /// **'AI-Powered Automotive Body Repair'**
  String get footerTagline;

  /// No description provided for @estimatorTitle.
  ///
  /// In en, this message translates to:
  /// **'Damage Estimator'**
  String get estimatorTitle;

  /// No description provided for @estimatorSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Upload a photo and get an instant AI repair estimate'**
  String get estimatorSubtitle;

  /// No description provided for @uploadPhoto.
  ///
  /// In en, this message translates to:
  /// **'Upload Photo'**
  String get uploadPhoto;

  /// No description provided for @takePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take Photo'**
  String get takePhoto;

  /// No description provided for @analyzeNow.
  ///
  /// In en, this message translates to:
  /// **'Analyze Now'**
  String get analyzeNow;

  /// No description provided for @estimateResult.
  ///
  /// In en, this message translates to:
  /// **'Estimate Result'**
  String get estimateResult;

  /// No description provided for @totalEstimate.
  ///
  /// In en, this message translates to:
  /// **'Total Estimate'**
  String get totalEstimate;

  /// No description provided for @orderNow.
  ///
  /// In en, this message translates to:
  /// **'Order Now'**
  String get orderNow;

  /// No description provided for @getEstimate.
  ///
  /// In en, this message translates to:
  /// **'Get Estimate'**
  String get getEstimate;

  /// No description provided for @severityLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get severityLight;

  /// No description provided for @severityMedium.
  ///
  /// In en, this message translates to:
  /// **'Moderate'**
  String get severityMedium;

  /// No description provided for @severityHeavy.
  ///
  /// In en, this message translates to:
  /// **'Heavy'**
  String get severityHeavy;

  /// No description provided for @panelDamage.
  ///
  /// In en, this message translates to:
  /// **'Panel Damage'**
  String get panelDamage;

  /// No description provided for @faqTitle.
  ///
  /// In en, this message translates to:
  /// **'FAQ & Support'**
  String get faqTitle;

  /// No description provided for @faqSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Find answers to common questions'**
  String get faqSubtitle;

  /// No description provided for @faqSearch.
  ///
  /// In en, this message translates to:
  /// **'Search questions…'**
  String get faqSearch;

  /// No description provided for @faqNoResults.
  ///
  /// In en, this message translates to:
  /// **'No questions found for your search.'**
  String get faqNoResults;

  /// No description provided for @contactSupport.
  ///
  /// In en, this message translates to:
  /// **'Contact Support'**
  String get contactSupport;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About Revive'**
  String get aboutTitle;

  /// No description provided for @aboutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Indonesia\'s premier AI-powered automotive body repair network'**
  String get aboutSubtitle;

  /// No description provided for @ourMission.
  ///
  /// In en, this message translates to:
  /// **'Our Mission'**
  String get ourMission;

  /// No description provided for @ourVision.
  ///
  /// In en, this message translates to:
  /// **'Our Vision'**
  String get ourVision;

  /// No description provided for @ourTeam.
  ///
  /// In en, this message translates to:
  /// **'Our Team'**
  String get ourTeam;

  /// No description provided for @privacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyTitle;

  /// No description provided for @privacyLastUpdated.
  ///
  /// In en, this message translates to:
  /// **'Last updated'**
  String get privacyLastUpdated;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'My Profile'**
  String get profileTitle;

  /// No description provided for @profileVehicles.
  ///
  /// In en, this message translates to:
  /// **'My Vehicles'**
  String get profileVehicles;

  /// No description provided for @profileOrders.
  ///
  /// In en, this message translates to:
  /// **'My Orders'**
  String get profileOrders;

  /// No description provided for @profileEditProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get profileEditProfile;

  /// No description provided for @profileChangePassword.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get profileChangePassword;

  /// No description provided for @profileNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get profileNotifications;

  /// No description provided for @profileSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get profileSettings;

  /// No description provided for @profileLogout.
  ///
  /// In en, this message translates to:
  /// **'Log Out'**
  String get profileLogout;

  /// No description provided for @addVehicle.
  ///
  /// In en, this message translates to:
  /// **'Add Vehicle'**
  String get addVehicle;

  /// No description provided for @vehiclePlate.
  ///
  /// In en, this message translates to:
  /// **'License Plate'**
  String get vehiclePlate;

  /// No description provided for @vehicleBrand.
  ///
  /// In en, this message translates to:
  /// **'Brand'**
  String get vehicleBrand;

  /// No description provided for @vehicleModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get vehicleModel;

  /// No description provided for @vehicleYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get vehicleYear;

  /// No description provided for @vehicleColor.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get vehicleColor;

  /// No description provided for @orderTitle.
  ///
  /// In en, this message translates to:
  /// **'Order Details'**
  String get orderTitle;

  /// No description provided for @orderStatus.
  ///
  /// In en, this message translates to:
  /// **'Order Status'**
  String get orderStatus;

  /// No description provided for @orderDate.
  ///
  /// In en, this message translates to:
  /// **'Order Date'**
  String get orderDate;

  /// No description provided for @orderTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get orderTotal;

  /// No description provided for @orderWorkshop.
  ///
  /// In en, this message translates to:
  /// **'Workshop'**
  String get orderWorkshop;

  /// No description provided for @checkoutTitle.
  ///
  /// In en, this message translates to:
  /// **'Checkout'**
  String get checkoutTitle;

  /// No description provided for @checkoutPayment.
  ///
  /// In en, this message translates to:
  /// **'Payment Method'**
  String get checkoutPayment;

  /// No description provided for @checkoutSummary.
  ///
  /// In en, this message translates to:
  /// **'Order Summary'**
  String get checkoutSummary;

  /// No description provided for @checkoutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Place Order'**
  String get checkoutConfirm;

  /// No description provided for @trackingTitle.
  ///
  /// In en, this message translates to:
  /// **'Live Tracking'**
  String get trackingTitle;

  /// No description provided for @trackingStatus.
  ///
  /// In en, this message translates to:
  /// **'Current Status'**
  String get trackingStatus;

  /// No description provided for @trackingWorkshop.
  ///
  /// In en, this message translates to:
  /// **'At Workshop'**
  String get trackingWorkshop;

  /// No description provided for @trackingEstimatedReady.
  ///
  /// In en, this message translates to:
  /// **'Estimated Ready'**
  String get trackingEstimatedReady;

  /// No description provided for @notificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notification Preferences'**
  String get notificationsTitle;

  /// No description provided for @notifRepairUpdates.
  ///
  /// In en, this message translates to:
  /// **'Repair Updates'**
  String get notifRepairUpdates;

  /// No description provided for @notifRepairUpdatesDesc.
  ///
  /// In en, this message translates to:
  /// **'Get notified on every repair milestone'**
  String get notifRepairUpdatesDesc;

  /// No description provided for @notifPromotions.
  ///
  /// In en, this message translates to:
  /// **'Promotions & Offers'**
  String get notifPromotions;

  /// No description provided for @notifPromotionsDesc.
  ///
  /// In en, this message translates to:
  /// **'Special deals and seasonal offers'**
  String get notifPromotionsDesc;

  /// No description provided for @notifReminders.
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get notifReminders;

  /// No description provided for @notifRemindersDesc.
  ///
  /// In en, this message translates to:
  /// **'Vehicle service and appointment reminders'**
  String get notifRemindersDesc;

  /// No description provided for @partnerDashboard.
  ///
  /// In en, this message translates to:
  /// **'Partner Dashboard'**
  String get partnerDashboard;

  /// No description provided for @partnerJobs.
  ///
  /// In en, this message translates to:
  /// **'Active Jobs'**
  String get partnerJobs;

  /// No description provided for @partnerWorkshop.
  ///
  /// In en, this message translates to:
  /// **'My Workshop'**
  String get partnerWorkshop;

  /// No description provided for @partnerEarnings.
  ///
  /// In en, this message translates to:
  /// **'Earnings'**
  String get partnerEarnings;

  /// No description provided for @partnerSettings.
  ///
  /// In en, this message translates to:
  /// **'Workshop Settings'**
  String get partnerSettings;

  /// No description provided for @partnerProfile.
  ///
  /// In en, this message translates to:
  /// **'Partner Profile'**
  String get partnerProfile;

  /// No description provided for @partnerStatus.
  ///
  /// In en, this message translates to:
  /// **'Workshop Status'**
  String get partnerStatus;

  /// No description provided for @statusOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get statusOnline;

  /// No description provided for @statusOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get statusOffline;

  /// No description provided for @statusBusy.
  ///
  /// In en, this message translates to:
  /// **'Busy'**
  String get statusBusy;

  /// No description provided for @jobAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept Job'**
  String get jobAccept;

  /// No description provided for @jobDecline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get jobDecline;

  /// No description provided for @jobComplete.
  ///
  /// In en, this message translates to:
  /// **'Mark Complete'**
  String get jobComplete;

  /// No description provided for @supportTitle.
  ///
  /// In en, this message translates to:
  /// **'Customer Support'**
  String get supportTitle;

  /// No description provided for @supportSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We\'re here to help'**
  String get supportSubtitle;

  /// No description provided for @supportChat.
  ///
  /// In en, this message translates to:
  /// **'Chat with Us'**
  String get supportChat;

  /// No description provided for @supportEmail.
  ///
  /// In en, this message translates to:
  /// **'Email Support'**
  String get supportEmail;

  /// No description provided for @supportPhone.
  ///
  /// In en, this message translates to:
  /// **'Call Support'**
  String get supportPhone;

  /// No description provided for @updatedAt.
  ///
  /// In en, this message translates to:
  /// **'Updated {date}'**
  String updatedAt(String date);

  /// No description provided for @jobIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Job #{id}'**
  String jobIdLabel(String id);

  /// No description provided for @panelCount.
  ///
  /// In en, this message translates to:
  /// **'{count} panel'**
  String panelCount(int count);
}

class _AppLDelegate extends LocalizationsDelegate<AppL> {
  const _AppLDelegate();

  @override
  Future<AppL> load(Locale locale) {
    return SynchronousFuture<AppL>(lookupAppL(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'id'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLDelegate old) => false;
}

AppL lookupAppL(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLEn();
    case 'id':
      return AppLId();
  }

  throw FlutterError(
      'AppL.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
