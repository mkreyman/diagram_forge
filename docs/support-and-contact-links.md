# Support, Contact, and Contribution Links

## Overview

Links for users to support the project financially, get in touch for business inquiries, and contribute to the codebase. All links visible to everyone (logged in or not).

## UI Layout

### Header (Top Navbar)

Text-based, minimal style visible to all users:

```
Support this project → GitHub | Stripe    ·    Get in touch
```

- **GitHub** → GitHub Sponsors (primary, recurring + one-time)
- **Stripe** → Payment Link (secondary, one-time tips)
- **Get in touch** → LinkedIn (business inquiries)

### Footer

```
© 2025 DiagramForge · Terms of Service · Privacy Policy · Support
```

- **Terms of Service** → `/terms` (needs to be created)
- **Privacy Policy** → `/privacy` (needs to be created)
- **Support** → GitHub Issues

---

## Configuration

All URLs pulled from environment variables:

```elixir
# config/runtime.exs
config :diagram_forge,
  # Contact
  linkedin_url: System.get_env("LINKEDIN_URL", "https://linkedin.com/in/mkreyman"),

  # Sponsorship
  github_sponsors_url: System.get_env("GITHUB_SPONSORS_URL", "https://github.com/sponsors/mkreyman"),
  stripe_tip_url: System.get_env("STRIPE_TIP_URL"),

  # Repository
  github_repo_url: System.get_env("GITHUB_REPO_URL", "https://github.com/mkreyman/diagram_forge"),
  github_issues_url: System.get_env("GITHUB_ISSUES_URL", "https://github.com/mkreyman/diagram_forge/issues"),

  # Legal
  terms_url: "/terms",
  privacy_url: "/privacy"
```

---

## Stripe Payment Link Setup

For one-time tips with customer-chosen amount:

1. Go to Stripe Dashboard → **Payment Links** → **Create**
2. Click **Add a new product** → Name it "Support DiagramForge" or "Tip"
3. Under pricing, select **"Customers choose what they pay"**
4. Set a suggested amount (e.g., $5) and minimum (e.g., $1)
5. **Payment type**: One-time (GitHub Sponsors handles recurring)
6. Customize the checkout page with your branding
7. Click **Create link**
8. Copy the link and set as `STRIPE_TIP_URL` env var

**Note:** GitHub Sponsors already handles recurring donations well, so Stripe is just for one-time tips from users who prefer not to use GitHub for payments.

---

## Implementation

### Header Component

```heex
<%!-- Visible to all users, in navbar --%>
<div class="flex items-center gap-2 text-sm text-slate-400">
  <span>Support this project →</span>
  <a
    href={Application.get_env(:diagram_forge, :github_sponsors_url)}
    target="_blank"
    rel="noopener"
    class="hover:text-slate-200 transition"
  >
    GitHub
  </a>
  <span>|</span>
  <a
    href={Application.get_env(:diagram_forge, :stripe_tip_url)}
    target="_blank"
    rel="noopener"
    class="hover:text-slate-200 transition"
  >
    Stripe
  </a>
  <span class="mx-2">·</span>
  <a
    href={Application.get_env(:diagram_forge, :linkedin_url)}
    target="_blank"
    rel="noopener"
    class="hover:text-slate-200 transition"
  >
    Get in touch
  </a>
</div>
```

### Footer Component

```heex
<footer class="bg-slate-900 border-t border-slate-800 py-4">
  <div class="container mx-auto px-4 text-center text-sm text-slate-500">
    <div class="flex flex-wrap items-center justify-center gap-x-4 gap-y-2">
      <span>© <%= Date.utc_today().year %> DiagramForge</span>
      <span class="hidden sm:inline">·</span>
      <a href="/terms" class="hover:text-slate-300 transition">Terms of Service</a>
      <span class="hidden sm:inline">·</span>
      <a href="/privacy" class="hover:text-slate-300 transition">Privacy Policy</a>
      <span class="hidden sm:inline">·</span>
      <a
        href={Application.get_env(:diagram_forge, :github_issues_url)}
        target="_blank"
        rel="noopener"
        class="hover:text-slate-300 transition"
      >
        Support
      </a>
    </div>
  </div>
</footer>
```

### Mobile Behavior

Standard responsive pattern:
- Header links collapse into hamburger menu on small screens
- Footer links wrap naturally with `flex-wrap`
- Separators hidden on mobile (`hidden sm:inline`)

---

## Setup Checklist

- [x] GitHub account
- [x] Stripe account
- [x] GitHub Sponsors enabled
- [x] `.github/FUNDING.yml` created
- [x] Stripe Payment Link created (one-time, customer-chosen price)
- [x] Terms of Service page (`/terms`)
- [x] Privacy Policy page (`/privacy`)
- [x] Environment variables configured in `config/runtime.exs`
- [x] Header component updated with support links
- [x] Footer component added with legal links

---

## Pages to Create

### Terms of Service (`/terms`)

Standard SaaS terms covering:
- Acceptable use
- Account responsibilities
- Service availability
- Limitation of liability
- Termination

### Privacy Policy (`/privacy`)

Required disclosures:
- Data collected (GitHub OAuth profile, diagrams created)
- How data is used
- Third-party services (GitHub, Stripe, hosting provider)
- Data retention
- User rights (access, deletion)
- Contact information
