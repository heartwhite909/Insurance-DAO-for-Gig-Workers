# 🛡️ Insurance DAO for Gig Workers

A decentralized insurance platform built on Stacks blockchain that enables freelancers and gig workers to collectively pool resources and provide mutual insurance coverage.

## 🌟 Features

- 💰 **Collective Pool**: Members contribute STX tokens to build a shared insurance fund
- 🗳️ **Democratic Claims**: Community votes on insurance claims with weighted voting based on contributions
- 📊 **Transparent Process**: All contributions, claims, and votes are recorded on-chain
- 🎯 **Fair Coverage**: Claims limited to 25% of total pool to ensure sustainability
- ⚡ **Instant Payouts**: Approved claims are paid out immediately from the pool

## 🚀 Getting Started

### Prerequisites
- Clarinet CLI installed
- Stacks wallet with STX tokens

### Installation

```bash
clarinet new insurance-dao-project
cd insurance-dao-project
```

Copy the contract code into `contracts/insurance-dao.clar`

## 📖 Usage Guide

### 🔐 Joining the DAO

```clarity
(contract-call? .insurance-dao join-dao u1000000)
```
Minimum contribution: 1 STX (1,000,000 microSTX)

### 💸 Making Additional Contributions

```clarity
(contract-call? .insurance-dao contribute u500000)
```

### 📝 Submitting Insurance Claims

```clarity
(contract-call? .insurance-dao submit-claim u2000000 "Equipment damage during client project")
```

### 🗳️ Voting on Claims

```clarity
(contract-call? .insurance-dao vote-on-claim u1 true)
```
- `true` = approve claim
- `false` = reject claim

### ✅ Finalizing Claims

```clarity
(contract-call? .insurance-dao finalize-claim u1)
```

### 💰 Claiming Payouts

```clarity
(contract-call? .insurance-dao payout-claim u1)
```

## 🔍 Query Functions

### Check Member Status
```clarity
(contract-call? .insurance-dao get-member-info 'SP1234...)
```

### View Pool Statistics
```clarity
(contract-call? .insurance-dao get-pool-stats)
```

### Check Claim Details
```clarity
(contract-call? .insurance-dao get-claim-info u1)
```

### Verify Voting Power
```clarity
(contract-call? .insurance-dao get-member-voting-power 'SP1234...)
```

## ⚖️ Governance Rules

- **Voting Period**: 144 blocks (~24 hours)
- **Approval Threshold**: 60% of active members must vote in favor
- **Voting Weight**: Based on total contributions
  - < 5 STX: 1 vote
  - 5-10 STX: 2 votes  
  - > 10 STX: 3 votes
- **Claim Limit**: Maximum 25% of total pool per claim

## 🛠️ Development

### Testing
```bash
clarinet test
```

### Console
```bash
clarinet console
```

### Deploy
```bash
clarinet deploy
```

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## 📄 License

This project is licensed under the MIT License.

## 🆘 Support

For support and questions, please open an issue in the GitHub repository.

---

Built with ❤️ for the gig economy community
```

**Git Commit Message:**
```
feat: implement MVP insurance DAO for gig workers with collective pooling and democratic claims voting
```

**GitHub Pull Request Title:**
```
🛡️ Add Insurance DAO MVP for Gig Workers - Collective Insurance Platform
```

**GitHub Pull Request Description:**
```
## 🎯 Overview
This PR introduces a Minimum Viable Product (MVP) for an Insurance DAO specifically designed for gig workers and freelancers.

## ✨ What's Added
- **Smart Contract**: Complete Clarity contract with 150+ lines implementing core insurance DAO functionality
- **Member Management**: Join/leave DAO with contribution tracking
- **Claims System**: Submit, vote on, and process insurance claims democratically  
- **Voting Mechanism**: Weighted voting based on member contributions
- **Pool Management**: Collective STX token pooling with transparent fund management
- **Documentation**: Comprehensive README with usage instructions and examples

## 🔧 Key Features
- Minimum 1 STX contribution to join
- Democratic claim approval (60% threshold)
- 24-hour voting periods
- Claims capped at 25% of total pool
- Weighted voting power based on contribution levels
- Instant payouts for approved claims

## 🧪 Technical Details
- Built with Clarity smart contract language
- Fully compatible with Stacks blockchain
- Ready for Clarinet testing and deployment
- Error handling for all edge cases
- Read-only functions for transparency

Ready for testing and community feedback! 🚀
