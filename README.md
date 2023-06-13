# PeaceFounder.jl

[![](https://img.shields.io/badge/docs-stable-blue.svg)](https://PeaceFounder.github.io/PeaceFounder.jl/stable)
[![](https://img.shields.io/badge/docs-dev-blue.svg)](https://PeaceFounder.github.io/PeaceFounder.jl/dev)

![](https://github.com/PeaceFounder/PeaceFounder.github.io/blob/master/_assets/vision.png?raw=true)

With the advancement of technology, remote electronic voting systems are becoming more prevalent in many contexts. Often the e-voting systems are designed as a two-step process where in the first step, voters cast encrypted votes, and, in the second step, the encrypted ballots are shuffled between different independent parties for anonymity and then decrypted. However, in these systems' privacy, transparency, and security remain in tension. Making all evidence public would violate the right of voters to keep their decision to participate secret, whereas including more parties who collectively decrypt the votes to ensure the anonymity of the voters could open adversaries an opportunity to prevent the election result from being decrypted or to assemble the entire decryption key providing means to know how exactly each voter had voted. 

An alternative approach is to anonymise voters instead of votes who cast them with a pseudonym. So far, proposed systems have focused on one-time large-scale elections where the relative generator is predetermined at the registration phase. That reduces complexity for the voter but puts a burden on the election authority to coordinate honest execution of re-encryption shuffle and threshold decryption between all involved parties. Although honesty of execution is guaranteed with zero-knowledge proofs, it does not prevent adversary-sabotaged communication issues. Thus, some baseline of trust is necessary for mixes to guarantee the reliability of the mix phase. 

PeaceFounder system differs from existing solutions by doing public key anonymisation for one mix at a time, after which the relative generator, zero-knowledge shuffle, and decryption proofs are published to the bulletin board. Since there is no coordination between mixes, it makes the protocol more reliable. It is important to note that this also makes the anonymisation easier to understand and more accessible to a broader audience as the mixing procedure is local and can be viewed as a function `braid(generator, members) -> (new_generator, new_members)` that can be visually represented as a knot-tying together multiple threads.

The PeaceFounder system demonstrates the feasibility of continuously enrolling new members who are anonymised equally with other members in subsequent mixings. The bulletin board is implemented as a Merkle tree where every new member, braid and proposal are recorded in a ledger, forming a transactional database available to everyone to verify. The clients are thin and use Merkle tree inclusion proofs to assert their membership and to get proof that an election authority provides a given proposal and can be held accountable for its correctness, including the relative generator with which the votes are being cast. To assert the integrity of the bulletin board, the clients would periodically download Merkle consistency proofs from the election authority.

One of the significant advantages of the PeaceFounder system over existing solutions is that a single person can deploy and maintain this system without compromising privacy, security or transparency. It does not rely on the trust of the honest execution of the ceremony for the setup parameters as it is with some cryptocurrency systems, nor does the need to coordinate correct threshold decryption between multiple parties as needed for a re-encryption-based mixnet voting system. This makes it more accessible to smaller communities which want to offer strong software-independent evidence to everyone and assure the members that their vote is anonymous, guaranteed with multiple braids made in different geographical locations.  

In addition to existing e-voting solutions, PeaceFounder is made with integration in mind. It's easy (when that will be documented) to use it in existing community webpages or forums, which have their own ways of selecting and authenticating members. Also, it is easy for the administrator to design procedures in which proposals get accepted for the members to vote and display the progress of the current and past proposals as they are being run. Even more unlimited options to design preferential cardinal or budget-constrained ballots are available while ensuring that election evidence provides software independence for everyone. Meanwhile, the votes are cast within a client GUI application offering security and privacy guarantees for the voters. In summary, if you use an e-voting solution on a website, you will benefit from transparency, security and privacy by using PeaceFounder with little to lose in usability. 

PeaceFounder system relies on established ElGamal re-encryption mixnet zero-knowledge proof of shuffle and digital signature algorithm. On top of that, it is assumed that an anonymous communication channel that prevents tracking by IP address is available. Thus a list of assumptions are:

- DDH hard ensuring computational anonymity;
- Infeasible to do a discrete logarithm;
- Anonymous channel over which to cast a vote;
- When evidence of misbehaving election authority is collected/presented, adequate local actions select a new replacement.

The PeaceFounder system is implemented in Julia with a client user interface written in QML and is available under Apache 2 license on GitHub. Currently, the system is demonstrated as a technical preview intended to test the usability of a happy path. Nevertheless, digital signatures are implemented in CryptoSignatures.jl complies with FIPS standards and re-encryption proof of shuffle is implemented in ShuffleProofs.jl complies with the Verificatum verifier. A proper specification for proof of correct decryption with a single party and canonicalisation of signed data is missing and will be fixed in the future. 

## Demo

For a demo, go to `PeaceFounderDemo` repository. A 10-minute youtube demonstration is available here:

[![IMAGE ALT TEXT HERE](https://img.youtube.com/vi/L7M0FG50ulU/maxresdefault.jpg)](https://www.youtube.com/watch?v=L7M0FG50ulU)
