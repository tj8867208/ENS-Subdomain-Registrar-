# 🌐 ENS Subdomain Registrar

A decentralized domain and subdomain registration system built on Stacks blockchain using Clarity smart contracts.

## ✨ Features

- 🏷️ **Domain Registration**: Register unique domain names with customizable expiry periods
- 🔗 **Subdomain Creation**: Create subdomains under owned domains
- 💰 **Revenue Sharing**: Domain owners earn fees from subdomain registrations
- 🔄 **Transfer System**: Transfer ownership of domains and subdomains
- ⏰ **Expiration Management**: Automatic expiration handling and renewal system
- 🛡️ **Access Control**: Secure ownership verification and admin functions

## 🚀 Quick Start

### Prerequisites
- Clarinet installed
- Stacks wallet with STX tokens

### Installation
```bash
git clone <repository-url>
cd ENS-Subdomain-Registrar
clarinet check
```

## 📖 Usage

### Register a Domain
```clarity
(contract-call? .ens-subdomain-registrar register-domain "mydomain" u144000)
```
- `name`: Domain name (max 64 characters)
- `duration`: Registration duration in blocks

### Register a Subdomain
```clarity
(contract-call? .ens-subdomain-registrar register-subdomain "mydomain" "api" )
```
- `domain`: Parent domain name
- `subdomain`: Subdomain name

### Transfer Domain
```clarity
(contract-call? .ens-subdomain-registrar transfer-domain "mydomain" 'SP1234567890)
```

### Transfer Subdomain
```clarity
(contract-call? .ens-subdomain-registrar transfer-subdomain "mydomain" "api" 'SP1234567890)
```

### Renew Domain
```clarity
(contract-call? .ens-subdomain-registrar renew-domain "mydomain" u144000)
```

## 🔍 Read-Only Functions

### Get Domain Information
```clarity
(contract-call? .ens-subdomain-registrar get-domain-info "mydomain")
```
Returns: `{owner: principal, expiry: uint, created-at: uint, subdomain-count: uint}`

### Get Subdomain Information
```clarity
(contract-call? .ens-subdomain-registrar get-subdomain-info "mydomain" "api")
```
Returns: `{owner: principal, created-at: uint, parent-domain: string}`

### Check Domain Revenue
```clarity
(contract-call? .ens-subdomain-registrar get-domain-revenue "mydomain")
```
Returns: `{total-earned: uint}`

### Get Registration Fees
```clarity
(contract-call? .ens-subdomain-registrar get-domain-registration-fee)
(contract-call? .ens-subdomain-registrar get-subdomain-registration-fee)
```

### Check Domain Expiry
```clarity
(contract-call? .ens-subdomain-registrar is-domain-expired "mydomain")
```

## 💡 Key Concepts

### 🏷️ Domain Logic
- **Primary Domains**: Top-level domains registered directly with the contract
- **Subdomains**: Secondary domains created under existing domains
- **Ownership**: Each domain and subdomain has a unique owner
- **Expiration**: Domains expire after a specified duration

### 💰 Fee Structure
- **Domain Registration**: Default 1 STX (1,000,000 microSTX)
- **Subdomain Registration**: Default 0.5 STX (500,000 microSTX)
- **Revenue Model**: Subdomain fees go to parent domain owner

### 🔐 Security Features
- Owner-only transfers
- Expiration checks
- Name validation
- Balance verification

## 🛠️ Admin Functions

### Set Registration Fees
```clarity
(contract-call? .ens-subdomain-registrar set-domain-registration-fee u2000000)
(contract-call? .ens-subdomain-registrar set-subdomain-registration-fee u1000000)
```

### Withdraw Contract Balance
```clarity
(contract-call? .ens-subdomain-registrar withdraw-contract-balance u1000000)
```

### Emergency Transfer
```clarity
(contract-call? .ens-subdomain-registrar emergency-transfer-domain "mydomain" 'SP1234567890)
```

## 🧪 Testing

Run the test suite:
```bash
clarinet test
```

## 📊 Contract Statistics

- **Total Lines**: 200+ lines of Clarity code
- **Functions**: 15+ public and read-only functions
- **Error Handling**: 10 different error types
- **Data Maps**: 3 storage maps for domains, subdomains, and revenues

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Submit a pull request

## 📄 License

MIT License - see LICENSE file for details

## 🌟 Future Enhancements

- 🎨 NFT integration for domain ownership
- 🔍 Advanced search and filtering
- 📊 Analytics dashboard
- 🌐 Web interface integration
- 💸 Auction system for premium domains

---

Built with ❤️ using Clarity and Stacks blockchain
