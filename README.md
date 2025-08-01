# 🌾 Crop Insurance Smart Contract System

A decentralized crop insurance platform built on Stacks blockchain that provides automated payouts to farmers based on weather data and crop failure reports from trusted oracles.

## 🚀 Features

- **🛡️ Policy Management**: Farmers can purchase insurance policies for their crops
- **🌦️ Weather Oracle Integration**: Automated payouts based on weather severity
- **📊 Crop Failure Reports**: Oracle-verified damage assessments
- **💰 Transparent Payouts**: Automatic claim processing based on predefined conditions
- **📋 Multi-Policy Support**: Farmers can hold multiple active policies

## 🏗️ Contract Architecture

### Core Components

- **Policy Management**: Create, manage, and cancel insurance policies
- **Oracle System**: Trusted data providers for weather and crop reports  
- **Automated Claims**: Smart contract logic determines payout eligibility
- **Fund Management**: Contract balance tracking and payout distribution

## 📖 Usage Guide

### For Contract Owner

#### 1. Set Oracle Address
```clarity
(contract-call? .crop-insurance set-oracle 'SP1234...ORACLE)
```

#### 2. Fund the Contract
```clarity
(contract-call? .crop-insurance fund-contract)
```

### For Farmers

#### 1. Purchase Insurance Policy
```clarity
(contract-call? .crop-insurance purchase-policy 
  "corn" 
  u1000000 
  u1000 
  "Iowa-Farm-District-1")
```

#### 2. Check Your Policies
```clarity
(contract-call? .crop-insurance get-farmer-policies tx-sender)
```

#### 3. Claim Payout
```clarity
(contract-call? .crop-insurance claim-payout u1)
```

### For Oracles

#### 1. Submit Weather Report
```clarity
(contract-call? .crop-insurance submit-weather-report 
  "Iowa-Farm-District-1" 
  25 
  u100 
  u80)
```

#### 2. Submit Crop Failure Report
```clarity
(contract-call? .crop-insurance submit-crop-failure-report u1 u75)
```

## 🔍 Read-Only Functions

- `get-policy`: Retrieve policy details by ID
- `get-farmer-policies`: Get all policies for a farmer
- `get-weather-report`: Fetch weather data for location/block
- `get-crop-failure-report`: Get damage report for policy
- `estimate-premium`: Calculate premium before purchase
- `estimate-payout`: Preview potential payout amount

## 💡 Payout Logic

Payouts are triggered when:
- **Crop damage ≥ 50%** OR **Weather severity ≥ 70%**
- **Full coverage**: When crop damage ≥ 80%
- **Partial coverage**: Proportional to damage percentage

## 🛠️ Development

### Prerequisites
- Clarinet CLI installed
- Stacks wallet for testing

### Local Testing
```bash
clarinet console
```

### Deploy to Testnet
```bash
clarinet deploy --testnet
```

## 📊 Contract Data

### Policy Structure
- Farmer address
- Crop type and location  
- Coverage amount and premium
- Policy duration (start/end blocks)
- Active status and claim history

### Weather Reports
- Location and timestamp
- Temperature, rainfall, severity score
- Oracle reporter verification

## 🔐 Security Features

- **Owner-only functions**: Oracle management restricted to contract owner
- **Oracle verification**: Only authorized oracles can submit reports
- **Double-claim prevention**: Policies can only be claimed once
- **Balance checks**: Ensures sufficient funds before payouts

## 🌟 Future Enhancements

- Multi-oracle consensus mechanism
- Dynamic premium calculation based on risk factors
- Integration with satellite imagery for crop monitoring
- Parametric insurance triggers for specific weather events

---

*Built with ❤️ for farmers worldwide using Stacks blockchain technology*
```

## Git Commit Message

```
feat: implement crop insurance smart contract MVP with oracle integration
```

## GitHub Pull Request Title

```
🌾 Add Crop Insurance Smart Contract System MVP
```

## GitHub Pull Request Description

```markdown
## Summary
This PR introduces a complete Crop Insurance Smart Contract System MVP that enables farmers to purchase insurance policies and receive automated payouts based on weather data and crop failure reports from trusted oracles.

## What's Added
- **Core Insurance Logic**: Policy creation, premium
