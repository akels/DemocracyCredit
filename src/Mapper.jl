module Mapper

import Sockets
import Dates: Dates, DateTime
using Base: UUID
using URIs: URI

import ..Schedulers: Schedulers, Scheduler, next_event
using ..Model
using ..Model: CryptoSpec, pseudonym, BraidChain, Registrar, PollingStation, TicketID, Membership, Proposal, Ballot, Selection, Transaction, Signer, BraidBroker, Pseudonym, Vote, id, DemeSpec, Digest, Admission, Ticket, Generator, GroupSpec


const RECORDER = Ref{Union{Signer, Nothing}}(nothing)
const REGISTRAR = Ref{Union{Registrar, Nothing}}(nothing)
const BRAIDER = Ref{Union{Signer, Nothing}}(nothing)
const COLLECTOR = Ref{Union{Signer, Nothing}}(nothing)
const PROPOSER = Ref{Union{Signer, Nothing}}(nothing)

# to prevent members registering while braiding happens and other way around.
# islocked() == false => lock else error in the case for a member
# wheras for braiding imediately lock is being waited for
const MEMBER_LOCK = ReentrantLock()
const BRAID_CHAIN = Ref{Union{BraidChain, Nothing}}(nothing)

const POLLING_STATION = Ref{Union{PollingStation, Nothing}}(nothing)
const TALLY_SCHEDULER = Scheduler(UUID, retry_interval = 5) 
const TALLY_PROCESS = Ref{Task}()

const ENTROPY_SCHEDULER = Scheduler(retry_interval = 1)
const ENTROPY_PROCESS = Ref{Task}()

const BRAID_BROKER = Ref{BraidBroker}
const BRAID_BROKER_SCHEDULER = Scheduler(retry_interval = 5)
const BRAID_BROKER_PROCESS = Ref{Task}()


function entropy_process_loop()
    
    uuid = wait(ENTROPY_SCHEDULER)
    bbox = Model.ballotbox(POLLING_STATION[], uuid)

    if isnothing(bbox.commit)

        spec = BRAID_CHAIN[].spec
        _seed = Model.digest(rand(UInt8, 16), Model.hasher(spec))
        Model.set_seed!(bbox, _seed)
        Model.commit!(bbox, COLLECTOR[]; with_tally = false)

    end

    return
end


function broker_process_loop(; force = false)

    force || wait(BRAID_BROKER_SCHEDULER)
    # no pooling thus no false triggers are expected here

    lock(MEMBER_LOCK)

    try
        _members = members(BRAID_CHAIN[])
        _braid = braid(BRAIDER_BROKER[], _members) # one is selected at random from all available options
    catch
        retry!(BRAID_BROKER_SCHEDULER)
    finally
        unlock(MEMBER_LOCK)
    end


    record!(BRAID_CHAIN[], _braid)
    commit!(BRAID_CHAIN[], RECORDER[])

    return
end

function tally_process_loop()
    
    uuid = wait(TALLY_SCHEDULER)
    tally_votes!(uuid)

    return
end


function setup(demefunc::Function, groupspec::GroupSpec, generator::Generator)

    BRAID_CHAIN[] = nothing # The braidchain needs to be loaded within a setup
    POLLING_STATION[] = nothing
    RECORDER[] = nothing
    REGISTRAR[] = nothing
    BRAIDER[] = nothing
    PROPOSER[] = nothing
    COLLECTOR[] = nothing

    key_list = Integer[]
    pseudonym_list = Pseudonym[]

    for i in 1:5
        (key, pseudonym) = Model.keygen(groupspec, generator)
        push!(key_list, key)
        push!(pseudonym_list, pseudonym)
    end

    demespec = demefunc(pseudonym_list)

    @assert groupspec == demespec.crypto.group "GroupSpec does not match argument"
    @assert verify(demespec, demespec.crypto) "DemeSpec is not corectly signed"

    # This covers a situation where braidchain is initialized externally
    # more work would need to be put to actually support that though
    if isnothing(BRAID_CHAIN[])
        BRAID_CHAIN[] = BraidChain(demespec)
    end

    if isnothing(POLLING_STATION[])
        POLLING_STATION[] = PollingStation(demespec.crypto)
    end


    N = findfirst(x->x==demespec.recorder, pseudonym_list)
    if !isnothing(N)
        RECORDER[] = Signer(demespec.crypto, generator, key_list[N])
        Model.record!(BRAID_CHAIN[], demespec)
        Model.commit!(BRAID_CHAIN[], RECORDER[]) 
    
        BRAID_BROKER_PROCESS[] = @async while true
            broker_process_loop()
        end
    end
    
    N = findfirst(x->x==demespec.registrar, pseudonym_list)
    if !isnothing(N)
        signer = Signer(demespec.crypto, generator, key_list[N])
        hmac_key = Model.bytes(Model.digest(Vector{UInt8}(string(key_list[N])), demespec.crypto)) # 
        REGISTRAR[] = Registrar(signer, hmac_key)
        Model.set_demehash!(REGISTRAR[], demespec) 
    end

    N = findfirst(x->x==demespec.braider, pseudonym_list)
    if !isnothing(N)
        BRAIDER[] = Signer(demespec.crypto, generator, key_list[N])
    end

    N = findfirst(x->x==demespec.proposer, pseudonym_list)
    if !isnothing(N)
        PROPOSER[] = Signer(demespec.crypto, generator, key_list[N])
    end    

    N = findfirst(x->x==demespec.collector, pseudonym_list)
    if !isnothing(N)
        COLLECTOR[] = Signer(demespec.crypto, generator, key_list[N])
   
        ENTROPY_PROCESS[] = @async while true
            entropy_process_loop()
        end

        TALLY_PROCESS[] = @async while true
            tally_process_loop()
        end
    end    

    return authorized_roles(demespec) # I may deprecate this in favour of a method.
end


function authorized_roles(demespec::DemeSpec)

    roles = []

    if !isnothing(RECORDER[]) && id(RECORDER[]) == demespec.recorder
        push!(roles, :recorder)
    end

    if !isnothing(REGISTRAR[]) && id(REGISTRAR[]) == demespec.registrar
        push!(roles, :registrar)
    end

    if !isnothing(BRAIDER[]) && id(BRAIDER[]) == demespec.braider
        push!(roles, :braider)
    end

    if !isnothing(COLLECTOR[]) && id(COLLECTOR[]) == demespec.collector
        push!(roles, :collector)
    end

    if !isnothing(PROPOSER[]) && id(PROPOSER[]) == demespec.proposer
        push!(roles, :proposer)
    end

    return roles
end


# Need to decide on whether this would be more appropriate
#system_roles() = (; recorder = id(RECORDER[]), registrar = id(REGISTRAR[]), braider = id(BRAIDER[]), collector = id(COLLECTOR[]))
tally_votes!(uuid::UUID) = Model.commit!(POLLING_STATION[], uuid, COLLECTOR[]; with_tally = true);

set_demehash(spec::DemeSpec) = Model.set_demehash!(REGISTRAR[], spec)
set_route(route::Union{URI, String}) = Model.set_route!(REGISTRAR[], route)
get_route() = REGISTRAR[].route

get_recruit_key() = Model.key(REGISTRAR[])

get_deme() = BRAID_CHAIN[].spec

enlist_ticket(ticketid::TicketID, timestamp::DateTime; expiration_time = nothing) = Model.enlist!(REGISTRAR[], ticketid, timestamp)
enlist_ticket(ticketid::TicketID; expiration_time = nothing) = enlist_ticket(ticketid, Dates.now(); expiration_time)

# Useful for an admin
#delete_ticket!(ticketid::TicketID) = Model.remove!(REGISTRAR[], ticketid) # 

get_ticket_ids() = Model.ticket_ids(REGISTRAR[])

get_ticket_status(ticketid::TicketID) = Model.ticket_status(ticketid, REGISTRAR[])
get_ticket_admission(ticketid::TicketID) = Model.select(Admission, ticketid, REGISTRAR[])
get_ticket_timestamp(ticketid::TicketID) = Model.select(Ticket, ticketid, REGISTRAR[]).timestamp

get_ticket(tokenid::AbstractString) = Model.select(Ticket, tokenid, REGISTRAR[])

# The benfit of refering to a single ticketid is that it is long lasting
seek_admission(id::Pseudonym, ticketid::TicketID) = Model.admit!(REGISTRAR[], id, ticketid) 
get_admission(id::Pseudonym) = Model.select(Admission, id, REGISTRAR[])
list_admissions() = [i.admission for i in REGISTRAR[].tickets]

get_chain_roll() = Model.roll(BRAID_CHAIN[])
get_member(_id::Pseudonym) = filter(x -> Model.id(x) == _id, list_members())[1] # Model.select

get_chain_commit() = Model.commit(BRAID_CHAIN[])

function submit_chain_record!(transaction::Transaction) 

    N = Model.record!(BRAID_CHAIN[], transaction)
    Model.commit!(BRAID_CHAIN[], RECORDER[])

    ack = Model.ack_leaf(BRAID_CHAIN[], N)
    return ack
end

get_chain_record(N::Int) = BRAID_CHAIN[][N]
get_chain_ack_leaf(N::Int) = Model.ack_leaf(BRAID_CHAIN[], N)
get_chain_ack_root(N::Int) = Model.ack_root(BRAID_CHAIN[], N)

enroll_member(member::Membership) = submit_chain_record!(member)
enlist_proposal(proposal::Proposal) = submit_chain_record!(proposal)

get_roll() = Model.roll(BRAID_CHAIN[])

get_peers() = Model.peers(BRAID_CHAIN[])

get_constituents() = Model.constituents(BRAID_CHAIN[])

reset_tree() = Model.reset_tree!(BRAID_CHAIN[])

get_members(N::Int) = Model.members(BRAID_CHAIN[], N)
get_members() = Model.members(BRAID_CHAIN[])

get_generator(N::Int) = Model.generator(BRAID_CHAIN[], N)
get_generator() = Model.generator(BRAID_CHAIN[])

get_chain_proposal_list() = collect(Model.list(Proposal, BRAID_CHAIN[]))


function schedule_pulse!(uuid::UUID, timestamp, nonceid)
    
    Model.schedule!(DEALER[], uuid, timestamp, nonceid)
    Schedulers.schedule!(DEALER_SCHEDULER, timestamp)

    return
end


function submit_chain_record!(proposal::Proposal)

    N = Model.record!(BRAID_CHAIN[], proposal)
    Model.commit!(BRAID_CHAIN[], RECORDER[])

    anchored_members = Model.members(BRAID_CHAIN[], proposal)
    Model.add!(POLLING_STATION[], proposal, anchored_members)

    Schedulers.schedule!(ENTROPY_SCHEDULER, proposal.open, proposal.uuid)
    Schedulers.schedule!(TALLY_SCHEDULER, proposal.closed, proposal.uuid)

    ack = Model.ack_leaf(BRAID_CHAIN[], N)
    return ack
end


function cast_vote(uuid::UUID, vote::Vote; late_votes = false)

    if !(Model.isstarted(proposal(uuid); time = Dates.now()))

        error("Voting have not yet started")

    elseif !late_votes && Model.isdone(proposal(uuid); time = Dates.now())

        error("Vote received for proposal too late")
        
    else
        # need to bounce back if not within window. It could still be allowed to 

        N = Model.record!(POLLING_STATION[], uuid, vote)
        Model.commit!(POLLING_STATION[], uuid, COLLECTOR[])

        ack = Model.ack_cast(POLLING_STATION[], uuid, N)
        return ack
    end
end

@deprecate cast_vote! cast_vote

ballotbox(uuid::UUID) = Model.ballotbox(POLLING_STATION[], uuid)
proposal(uuid::UUID) = ballotbox(uuid).proposal
tally(uuid::UUID) = ballotbox(uuid).tally

get_ballotbox_commit(uuid::UUID) = Model.commit(POLLING_STATION[], uuid)

get_ballotbox_ack_leaf(uuid::UUID, N::Int) = Model.ack_leaf(POLLING_STATION[], uuid, N)
get_ballotbox_ack_root(uuid::UUID, N::Int) = Model.ack_root(POLLING_STATION[], uuid, N)

get_ballotbox_spine(uuid::UUID) = Model.spine(POLLING_STATION[], uuid)

function get_ballotbox_record(uuid::UUID, N::Int; fairness::Bool = true)
   
    bbox = Model.ballotbox(PollingStation[], uuid)        
    
    # If fair then only when the tally is published the vote can be accessed
    if fairness && isnothing(bbox.tally) || !fairness
        Model.record(bbox, N)
    else
        error("Due to fairness individual votes will be available only after tallly will be committed by the collector")
    end

end

get_ballotbox_receipt(uuid::UUID, N::Int) = Model.receipt(POOLING_STATION[], uuid, N)


function get_ballotbox_ledger(uuid::UUID; fairness::Bool = true, tally_trigger_delay::Union{Nothing, Int} = nothing)

    bbox = Model.ballotbox(PollingStation[], uuid)        

    trigger_tally!(uuid; tally_trigger_delay)
    # If fair then only when the tally is published the vote can be accessed
    if fairness && isnothing(bbox.tally) || !fairness
        Model.ledger(bbox)
    else
        error("Due to fairness individual votes will be available only after tallly will be committed by the collector")
    end

end


end
