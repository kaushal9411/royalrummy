# Cost Estimation — RummyRoyale

## 1. Infrastructure Costs (Monthly, Production)

### AWS Services

| Service                        | Config                        | Monthly Cost (USD) |
|-------------------------------|-------------------------------|-------------------|
| EKS Cluster                   | 1 cluster                     | $73               |
| EKS Worker Nodes (App)        | t3.xlarge × 8                 | $1,120            |
| EKS Worker Nodes (Game/WS)    | c5.2xlarge × 5                | $700              |
| RDS PostgreSQL                | db.r6g.2xlarge, Multi-AZ      | $950              |
| ElastiCache Redis Cluster     | cache.r6g.xlarge × 3          | $650              |
| Application Load Balancer     | 1 ALB                         | $25               |
| NAT Gateway                   | 2 AZ                          | $90               |
| S3 (assets + backups)         | ~500GB + requests             | $40               |
| CloudFront CDN                | ~10TB transfer/month          | $120              |
| Route53                       | 1 hosted zone                 | $5                |
| ACM (SSL)                     | Free                          | $0                |
| CloudWatch Logs               | ~500GB/month                  | $125              |
| Data Transfer Out             | ~5TB/month                    | $225              |
| **Total AWS**                 |                               | **~$4,123/month** |

### Third-Party Services

| Service            | Plan                          | Monthly Cost (USD) |
|--------------------|-------------------------------|-------------------|
| Cloudflare         | Pro ($20) or Business ($200)  | $200              |
| Firebase (Blaze)   | Pay-per-use                   | $100              |
| Sentry             | Team plan                     | $26               |
| Razorpay           | 2% per transaction            | Variable          |
| Twilio/MSG91 (SMS) | Per SMS (₹0.15 per OTP)       | $50               |
| AWS SES (Email)    | Per email                     | $10               |
| **Total 3rd Party**|                               | **~$386/month**   |

**Total Infrastructure: ~$4,500/month (~₹3.75 lakhs/month)**

---

## 2. Development Costs (One-Time)

### Team (6 months to launch)

| Role                      | Monthly (USD) | 6-Month Total |
|---------------------------|---------------|---------------|
| Lead Backend Engineer ×1  | $4,000        | $24,000       |
| Backend Engineer ×2       | $3,000        | $36,000       |
| Flutter Developer ×2      | $3,000        | $36,000       |
| DevOps Engineer ×1        | $4,000        | $24,000       |
| Frontend (Next.js) ×1     | $3,000        | $18,000       |
| QA Engineer ×1            | $2,000        | $12,000       |
| Product Manager ×1        | $3,500        | $21,000       |
| **Total (India rates)**   |               | **$171,000**  |
| **In INR (~₹83/USD)**    |               | **~₹1.42 Cr** |

### Licensing & Setup

| Item                          | Cost (USD) |
|-------------------------------|------------|
| Play Store Developer Account  | $25        |
| Apple Developer Account       | $99/year   |
| Legal/Compliance Review       | $5,000     |
| Security Audit (PenTest)      | $5,000     |
| Game Art & Design             | $10,000    |
| Sound Design                  | $3,000     |
| **Total Setup**               | **~$23,000**|

---

## 3. Operational Cost at Scale

### 100K Daily Active Users

| Category                  | Monthly (INR)     |
|---------------------------|-------------------|
| AWS Infrastructure        | ₹3,75,000         |
| Third-party Services      | ₹32,000           |
| Engineering Team (10 ppl) | ₹25,00,000        |
| Marketing & UA            | ₹15,00,000        |
| Customer Support (5 ppl)  | ₹3,00,000         |
| Legal & Compliance        | ₹50,000           |
| Payment Gateway Fees      | Variable (2%)     |
| **Total Monthly Opex**    | **~₹48,00,000**   |

---

## 4. Revenue Projection

### Assumptions
- 100K DAU after 6 months
- 25% depositing rate = 25,000 daily depositing users
- Average deposit: ₹200/user/day
- 10% platform rake
- 15% tournament rake

| Metric                    | Monthly               |
|---------------------------|-----------------------|
| Total Money in Games      | ₹5,00,00,000 (5 Cr)  |
| Platform Rake (10%)       | ₹50,00,000            |
| Tournament Revenue (15%)  | ₹10,00,000            |
| VIP Memberships (5K users)| ₹5,00,000             |
| **Gross Revenue**         | **₹65,00,000**        |
| Operational Costs         | ₹48,00,000            |
| **Net Profit**            | **₹17,00,000**        |
| **Net Margin**            | **26%**               |

### Break-Even Analysis
- Break-even at ~55K DAU with current cost structure
- Estimated break-even: Month 8-9 post-launch

---

## 5. Scaling Cost Projections

| Users          | Monthly Infra | Monthly Revenue | Monthly Profit |
|----------------|---------------|-----------------|----------------|
| 10K DAU        | ₹1,50,000     | ₹8,00,000       | -₹37,00,000    |
| 50K DAU        | ₹2,50,000     | ₹35,00,000      | -₹10,00,000    |
| 100K DAU       | ₹4,00,000     | ₹65,00,000      | +₹17,00,000    |
| 500K DAU       | ₹18,00,000    | ₹3,00,00,000    | +₹2,32,00,000  |
| 1M DAU         | ₹35,00,000    | ₹6,00,00,000    | +₹5,25,00,000  |

*Note: Operational/team costs scale sub-linearly with users due to infrastructure efficiency*

---

## 6. Third-Party Services Recommended

| Purpose              | Recommended Service         | Alternative           |
|----------------------|-----------------------------|-----------------------|
| Payment Gateway      | Razorpay                    | Cashfree, PayU        |
| SMS OTP              | MSG91                       | Twilio, 2Factor       |
| Email                | AWS SES                     | SendGrid              |
| CDN                  | Cloudflare                  | AWS CloudFront        |
| Crash Analytics      | Firebase Crashlytics        | Sentry                |
| Error Tracking       | Sentry                      | Rollbar               |
| APM                  | Datadog                     | New Relic             |
| Log Management       | Elasticsearch (self-hosted) | Datadog Logs          |
| KYC Verification     | Digio / Karza               | Hyperverge            |
| Bank Account Verify  | Razorpay Route              | Cashfree              |
| Fraud Detection      | Sift Science                | Custom ML             |
| Analytics            | Firebase + BigQuery         | Mixpanel, Amplitude   |
| Feature Flags        | Firebase Remote Config      | LaunchDarkly          |
| Load Testing         | k6                          | Locust, JMeter        |
| Code Quality         | SonarQube                   | CodeClimate           |

---

## 7. Legal & Compliance (India)

```
Required Registrations:
  ✓ Company Registration (Private Limited)
  ✓ GST Registration (mandatory for gaming)
  ✓ Payment Aggregator License (if own gateway)
  ✓ Skill Gaming License (state-specific)

Restricted States (real-money gaming not allowed):
  ✗ Andhra Pradesh
  ✗ Telangana
  ✗ Odisha
  ✗ Assam
  ✗ Nagaland (separate license required)
  ✗ Sikkim (separate license required)

Tax Compliance:
  ✓ 28% GST on platform fees
  ✓ 30% TDS on net winnings > ₹10,000 per withdrawal
  ✓ Annual 26AS/TDS filing for users
  ✓ IT Returns with gaming income disclosure

Legal: Budget ₹5-10 lakhs for initial legal setup
```
