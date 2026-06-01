// Purpose: In-app legal document viewer — Privacy Policy and Terms of Service.
import 'package:buildercam/core/app_colors.dart';
import 'package:buildercam/core/app_spacing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

enum LegalDocument { privacy, terms }

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPrivacy = document == LegalDocument.privacy;

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(isPrivacy ? 'Privacy Policy' : 'Terms of Service'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s5,
          vertical: AppSpacing.s6,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: isPrivacy ? _privacySections(theme) : _termsSections(theme),
          ),
        ),
      ),
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

TextStyle _h1(ThemeData t) =>
    t.textTheme.titleLarge!.copyWith(fontWeight: FontWeight.w800, height: 1.3);

TextStyle _h2(ThemeData t) => t.textTheme.titleMedium!.copyWith(
      fontWeight: FontWeight.w700,
      color: AppColors.body,
      height: 1.4,
    );

TextStyle _h3(ThemeData t) => t.textTheme.bodyLarge!.copyWith(
      fontWeight: FontWeight.w700,
      color: AppColors.body,
    );

TextStyle _body(ThemeData t) =>
    t.textTheme.bodyMedium!.copyWith(color: AppColors.bodyMuted, height: 1.7);

TextStyle _link(ThemeData t) => _body(t).copyWith(
      color: AppColors.primary,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.primary,
    );

Widget _gap([double h = 12]) => SizedBox(height: h);

Widget _title(ThemeData t, String text) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: _h1(t)),
        _gap(4),
      ],
    );

Widget _meta(ThemeData t) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Effective Date: May 29, 2026  ·  Last Updated: May 29, 2026',
          style: _body(t).copyWith(fontSize: 12),
        ),
        _gap(24),
      ],
    );

Widget _section(ThemeData t, String number, String heading, List<Widget> children) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _gap(28),
      Text('$number. $heading', style: _h2(t)),
      _gap(10),
      ...children,
    ],
  );
}

Widget _sub(ThemeData t, String heading, List<Widget> children) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _gap(16),
      Text(heading, style: _h3(t)),
      _gap(6),
      ...children,
    ],
  );
}

Widget _p(ThemeData t, String text) =>
    Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(text, style: _body(t)));

Widget _pRich(ThemeData t, List<InlineSpan> spans) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text.rich(TextSpan(children: spans, style: _body(t))),
    );

Widget _bullets(ThemeData t, List<String> items) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items
          .map(
            (item) => Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 8),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: AppColors.bodyMuted,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(child: Text(item, style: _body(t))),
                ],
              ),
            ),
          )
          .toList(),
    );

TextSpan _linkSpan(ThemeData t, String text, String url) => TextSpan(
      text: text,
      style: _link(t),
      recognizer: TapGestureRecognizer()
        ..onTap = () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
    );

// ── Privacy Policy content ────────────────────────────────────────────────────

List<Widget> _privacySections(ThemeData t) => [
      _title(t, 'Privacy Policy'),
      _meta(t),
      _p(t,
          'TechBacked ("BuilderCam," "we," "our," or "us") operates the BuilderCam mobile application and website (collectively, the "Service"). This Privacy Policy explains what information we collect, how we use it, and your rights regarding that information. By using the Service, you agree to the practices described here.'),

      _section(t, '1', 'Information We Collect', [
        _sub(t, 'Account Information', [
          _p(t, 'When you register, we collect your name, email address, and password (stored as a secure hash via Firebase Authentication).'),
        ]),
        _sub(t, 'Video & Audio Recordings', [
          _p(t, 'The core function of BuilderCam is recording job-site walkthroughs. Video and audio files you record are uploaded to and stored in Google Cloud Storage (Firebase Storage). These recordings are processed by AI services to generate transcripts and Statements of Work.'),
        ]),
        _sub(t, 'Documents & Content', [
          _p(t, 'We store generated Statements of Work, transcripts, client information you enter, and any documents you create or upload through the Service in our Firestore database.'),
        ]),
        _sub(t, 'Usage & Log Data', [
          _p(t, 'We automatically collect information about how you interact with the Service, including IP address, device type, operating system, browser type, pages visited, features used, and timestamps. This data is used to operate, secure, and improve the Service.'),
        ]),
        _sub(t, 'Payment Information', [
          _p(t, 'We do not store your credit card or payment details. All billing is handled by Paddle.com Market Ltd., our payment processor.'),
        ]),
        _sub(t, 'Team & Collaboration Data', [
          _p(t, 'If you use team features, we store information about your team members, their roles, and their activity within your account.'),
        ]),
      ]),

      _section(t, '2', 'How We Use Your Information', [
        _bullets(t, [
          'Provide, maintain, and improve the Service',
          'Process and transcribe video recordings to generate Statements of Work',
          'Manage your account, subscription, and team',
          'Process payments and send billing-related communications',
          'Send transactional emails (receipts, password resets, document notifications)',
          'Respond to support requests and communications',
          'Monitor for fraudulent or abusive activity and enforce our Terms',
          'Comply with legal obligations',
          'With your consent, send product updates and marketing communications (you may opt out at any time)',
        ]),
        _gap(8),
        _p(t, 'We do not sell your personal data to third parties.'),
      ]),

      _section(t, '3', 'How We Share Your Information', [
        _p(t, 'We share data only as necessary to operate the Service:'),
        _sub(t, 'Service Providers', [
          _bullets(t, [
            'Google Firebase — authentication, database (Firestore), and file storage',
            'OpenAI — AI transcription and SOW generation (audio/video content may be processed by OpenAI\'s API)',
            'Paddle.com Market Ltd. — subscription billing and payment processing (acts as Merchant of Record)',
            'Email delivery providers — for transactional and product emails',
          ]),
        ]),
        _sub(t, 'Legal Requirements', [
          _p(t, 'We may disclose your information if required to do so by law or in response to valid legal process (e.g., a court order or subpoena).'),
        ]),
        _sub(t, 'Business Transfers', [
          _p(t, 'If BuilderCam is acquired or merges with another company, your data may be transferred as part of that transaction. We will notify you via email or a prominent notice on the Service before your data becomes subject to a different privacy policy.'),
        ]),
        _p(t, 'We do not share your data for advertising purposes.'),
      ]),

      _section(t, '4', 'Payments & Billing', [
        _pRich(t, [
          const TextSpan(text: 'BuilderCam uses '),
          TextSpan(text: 'Paddle.com Market Ltd.', style: _body(t).copyWith(fontWeight: FontWeight.w700)),
          const TextSpan(text: ' ("Paddle") as its Merchant of Record for all subscription billing. When you purchase a subscription:'),
        ]),
        _bullets(t, [
          'Your payment is processed directly by Paddle',
          'Paddle collects your billing name, address, and payment card details',
          'Paddle may share a transaction reference with us to provision your subscription',
          'We never see or store your full payment card details',
        ]),
        _pRich(t, [
          const TextSpan(text: 'Paddle\'s '),
          _linkSpan(t, 'Privacy Policy', 'https://www.paddle.com/legal/privacy'),
          const TextSpan(text: ' governs how your billing data is handled.'),
        ]),
      ]),

      _section(t, '5', 'Data Retention', [
        _p(t, 'We retain your data for as long as your account is active or as needed to provide the Service. If you delete your account, we will delete or anonymise your personal data within 30 days, except where we are required to retain it by law (e.g., financial records for tax purposes, which may be retained for up to 7 years).'),
        _p(t, 'Video recordings and associated transcripts are retained until you delete them or close your account.'),
      ]),

      _section(t, '6', 'Security', [
        _p(t, 'We implement industry-standard security measures including:'),
        _bullets(t, [
          'TLS/HTTPS encryption for all data in transit',
          'Firebase Security Rules to restrict data access to authorised users',
          'Hashed and salted password storage via Firebase Authentication',
          'Regular security reviews',
        ]),
        _p(t, 'No method of transmission over the internet or electronic storage is 100% secure. We cannot guarantee absolute security, but we are committed to protecting your data.'),
      ]),

      _section(t, '7', 'Cookies & Tracking', [
        _p(t, 'The BuilderCam mobile app does not use cookies. Our website uses essential cookies necessary for the website to function, and may use analytics cookies (e.g., to understand how visitors interact with the site). You can control cookie preferences through your browser settings.'),
      ]),

      _section(t, '8', 'Your Rights', [
        _p(t, 'Depending on your location, you may have the following rights regarding your personal data:'),
        _bullets(t, [
          'Access — request a copy of the personal data we hold about you',
          'Rectification — request correction of inaccurate data',
          'Erasure — request deletion of your data ("right to be forgotten")',
          'Portability — request your data in a machine-readable format',
          'Objection — object to certain types of processing',
          'Restriction — request that we restrict processing of your data',
        ]),
        _pRich(t, [
          const TextSpan(text: 'To exercise any of these rights, please contact us at '),
          _linkSpan(t, 'support@buildercam.ai', 'mailto:support@buildercam.ai'),
          const TextSpan(text: '. We will respond within 30 days.'),
        ]),
      ]),

      _section(t, '9', "Children's Privacy", [
        _p(t, 'The Service is not directed to individuals under the age of 18. We do not knowingly collect personal data from children. If you believe we have inadvertently collected data from a child, please contact us immediately at support@buildercam.ai and we will delete the information promptly.'),
      ]),

      _section(t, '10', 'Changes to This Policy', [
        _p(t, 'We may update this Privacy Policy from time to time. We will notify you of material changes by email or by displaying a notice within the Service at least 14 days before the change takes effect. Your continued use of the Service after the effective date constitutes acceptance of the updated policy.'),
      ]),

      _section(t, '11', 'Contact Us', [
        _pRich(t, [
          const TextSpan(text: 'If you have questions about this Privacy Policy or our data practices, please contact us at '),
          _linkSpan(t, 'support@buildercam.ai', 'mailto:support@buildercam.ai'),
          const TextSpan(text: ' or by mail: TechBacked, Privacy Team, [Company Address].'),
        ]),
      ]),

      _gap(40),
    ];

// ── Terms of Service content ──────────────────────────────────────────────────

List<Widget> _termsSections(ThemeData t) => [
      _title(t, 'Terms of Service'),
      _meta(t),
      _p(t,
          'Please read these Terms of Service carefully before using the BuilderCam platform. By accessing or using the Service, you agree to be bound by these Terms.'),

      _section(t, '1', 'Acceptance of Terms', [
        _p(t,
            'By creating an account or using the BuilderCam mobile application or website (collectively, the "Service"), you agree to be bound by these Terms of Service ("Terms") and our Privacy Policy. If you do not agree, do not use the Service.'),
        _p(t,
            'If you are using the Service on behalf of a company or other organisation, you represent that you have authority to bind that organisation to these Terms.'),
      ]),

      _section(t, '2', 'The Service', [
        _p(t, 'BuilderCam is a software-as-a-service platform that enables contractors and tradespeople to:'),
        _bullets(t, [
          'Record video and audio walkthroughs of job sites',
          'Automatically generate AI-powered Statements of Work (SOW) from those recordings',
          'Send, manage, and obtain e-signatures on SOW documents',
          'Manage jobs, teams, and client communications',
        ]),
        _p(t,
            'We reserve the right to modify, suspend, or discontinue any part of the Service at any time with reasonable notice. We are not liable to you or any third party for any such changes.'),
      ]),

      _section(t, '3', 'Accounts & Eligibility', [
        _p(t, 'To use the Service, you must:'),
        _bullets(t, [
          'Be at least 18 years of age',
          'Provide accurate and complete registration information',
          'Keep your account credentials confidential',
          'Notify us immediately of any unauthorised use of your account',
        ]),
        _p(t,
            'You are responsible for all activity that occurs under your account. BuilderCam is not liable for any loss arising from unauthorised access to your account due to your failure to keep credentials secure.'),
      ]),

      _section(t, '4', 'Subscriptions & Billing', [
        _sub(t, 'Merchant of Record', [
          _pRich(t, [
            const TextSpan(text: 'All purchases through BuilderCam are processed by '),
            TextSpan(text: 'Paddle.com Market Ltd.', style: _body(t).copyWith(fontWeight: FontWeight.w700)),
            const TextSpan(text: ' ("Paddle"), which acts as the Merchant of Record. Your contract for purchase is with Paddle. Paddle\'s '),
            _linkSpan(t, 'Terms of Service', 'https://www.paddle.com/legal/terms'),
            const TextSpan(text: ' and '),
            _linkSpan(t, 'Privacy Policy', 'https://www.paddle.com/legal/privacy'),
            const TextSpan(text: ' apply to all transactions.'),
          ]),
        ]),
        _sub(t, 'Credits & Plans', [
          _p(t,
              'BuilderCam is a credits-based platform. Each SOW generation uses one credit. Credits can be purchased as one-time packs or through a monthly subscription plan. Current pricing is available in the app\'s billing section.'),
        ]),
        _sub(t, 'Billing Cycle', [
          _p(t,
              'Subscriptions are billed in advance on a recurring monthly basis. Your subscription will automatically renew at the end of each billing period unless you cancel before the renewal date.'),
        ]),
        _sub(t, 'Credits', [
          _p(t, 'Credits purchased as one-time packs never expire. Monthly subscription credits that are unused at the end of a billing cycle roll over to the next period.'),
        ]),
        _sub(t, 'Price Changes', [
          _p(t,
              'We reserve the right to change prices with at least 30 days\' notice. Price changes will not affect your current billing period. Your continued use of the Service after a price change constitutes acceptance of the new price.'),
        ]),
      ]),

      _section(t, '5', 'Refund Policy', [
        _pRich(t, [
          const TextSpan(text: 'If you are not satisfied with BuilderCam, you may request a full refund within '),
          TextSpan(text: '14 days', style: _body(t).copyWith(fontWeight: FontWeight.w700)),
          const TextSpan(text: ' of your initial purchase or renewal date by contacting '),
          _linkSpan(t, 'support@buildercam.ai', 'mailto:support@buildercam.ai'),
          const TextSpan(text: '. Refund requests after this period will be evaluated on a case-by-case basis.'),
        ]),
        _p(t,
            'Refunds are processed through Paddle and may take 5–10 business days to appear on your statement, depending on your payment method and bank.'),
      ]),

      _section(t, '6', 'Acceptable Use', [
        _p(t, 'You agree not to use the Service to:'),
        _bullets(t, [
          'Record individuals without their knowledge or consent where required by applicable law',
          'Upload, transmit, or store content that is illegal, defamatory, threatening, or fraudulent',
          'Violate any applicable laws or regulations',
          'Attempt to gain unauthorised access to the Service or its infrastructure',
          'Reverse-engineer, decompile, or disassemble any part of the Service',
          'Use the Service to compete with BuilderCam or to develop a competing product',
          'Transmit spam, malware, or any harmful code',
        ]),
        _p(t, 'We reserve the right to suspend or terminate your account immediately for any violation of this section.'),
      ]),

      _section(t, '7', 'Your Content', [
        _p(t,
            'You retain ownership of all video recordings, documents, and other content you upload to the Service ("Your Content"). By uploading Your Content, you grant BuilderCam a limited, non-exclusive, worldwide licence to process, store, and transmit Your Content solely to provide the Service to you.'),
        _p(t,
            'You are solely responsible for Your Content and represent that you have all necessary rights, consents, and permissions to upload and use it through the Service.'),
      ]),

      _section(t, '8', 'Intellectual Property', [
        _p(t,
            'The Service, including all software, designs, trademarks, logos, and generated SOW templates, is the property of TechBacked and is protected by intellectual property laws. These Terms do not transfer any ownership rights to you.'),
      ]),

      _section(t, '9', 'Third-Party Services', [
        _p(t,
            'The Service integrates with third-party services including Google Firebase, OpenAI, and Paddle. Your use of those services is governed by their respective terms and privacy policies. BuilderCam is not responsible for the practices or content of third-party services.'),
      ]),

      _section(t, '10', 'Disclaimers', [
        _p(t,
            'THE SERVICE IS PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT WARRANTIES OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NON-INFRINGEMENT.'),
        _p(t,
            'BuilderCam does not warrant that the Service will be uninterrupted, error-free, or completely secure. AI-generated Statements of Work are provided for informational purposes and should be reviewed by a qualified professional before use.'),
      ]),

      _section(t, '11', 'Limitation of Liability', [
        _p(t,
            'TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, BUILDERCAM SHALL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, INCLUDING LOSS OF PROFITS, DATA, GOODWILL, OR BUSINESS INTERRUPTION, ARISING OUT OF OR IN CONNECTION WITH THESE TERMS OR YOUR USE OF THE SERVICE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.'),
        _p(t,
            'OUR TOTAL LIABILITY TO YOU FOR ALL CLAIMS ARISING UNDER THESE TERMS SHALL NOT EXCEED THE AMOUNT YOU PAID TO BUILDERCAM IN THE 12 MONTHS PRECEDING THE CLAIM.'),
      ]),

      _section(t, '12', 'Indemnification', [
        _p(t,
            'You agree to indemnify, defend, and hold harmless TechBacked and its affiliates, officers, directors, employees, and agents from and against any claims, liabilities, damages, losses, and expenses (including reasonable legal fees) arising out of or in connection with your use of the Service, Your Content, or your violation of these Terms.'),
      ]),

      _section(t, '13', 'Termination', [
        _p(t,
            'You may delete your account at any time by contacting support@buildercam.ai. We may suspend or terminate your access to the Service at any time for any reason, including violation of these Terms, with or without notice.'),
        _p(t,
            'Upon termination, your right to use the Service ceases immediately. Sections on intellectual property, disclaimers, limitation of liability, and governing law survive termination.'),
      ]),

      _section(t, '14', 'Governing Law', [
        _p(t,
            'These Terms are governed by the laws of the State of Delaware, United States, without regard to its conflict of law principles. Any disputes arising from these Terms or the Service shall be resolved exclusively in the courts of Delaware, and you consent to personal jurisdiction in those courts.'),
      ]),

      _section(t, '15', 'Changes to These Terms', [
        _p(t,
            'We may update these Terms from time to time. We will notify you of material changes by email or by displaying a notice within the Service at least 14 days before the change takes effect. Your continued use of the Service after the effective date constitutes acceptance of the updated Terms.'),
      ]),

      _section(t, '16', 'Contact Us', [
        _pRich(t, [
          const TextSpan(text: 'If you have questions about these Terms, please contact us at '),
          _linkSpan(t, 'support@buildercam.ai', 'mailto:support@buildercam.ai'),
          const TextSpan(text: '.'),
        ]),
      ]),

      _gap(40),
    ];
