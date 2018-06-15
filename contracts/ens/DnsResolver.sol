pragma solidity ^0.4.23;

// Copyright © 2017 Weald Technology Trading Limited
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import './PublicResolver.sol';
import './RRUtils.sol';
import './AbstractENS.sol';


/**
 * @title DnsResolver
 *        A DNS resolver that handles all common types of DNS resource record,
 *        plus the ability to expand to new types arbitrarily.
 *
 *        Definitions used within this contract are as follows:
 *          - node is the namehash of the ENS domain e.g. namehash('myzone.eth')
 *          - name is the keccak-256 hash of the fully-qualified name of the node e.g. keccak256('www.myzone.eth.') (note the trailing period)
 *          - resource is the numeric ID of the record from https://en.wikipedia.org/wiki/List_of_DNS_record_types
 *          - data is DNS wire format data for the record
 *
 *        State of this contract: under development; ABI not finalised and subject
 *        to change.  Do not use.
 *
 * @author Jim McDonald
 * @notice If you use this contract please consider donating some Ether or
 *         some of your ERC-20 token to wsl.wealdtech.eth to support continued
 *         development of these and future contracts
 */
contract DnsResolver is PublicResolver {
    using RRUtils for *;
    using BytesUtils for bytes;

    // Complete zones
    mapping(bytes32=>bytes) public zones;

    // node => name => resource => data
    mapping(bytes32=>mapping(bytes32=>mapping(uint16=>bytes))) public records;

    // The ENS registry
    AbstractENS registry;

    // Restrict operations to the owner of the relevant ENS node
    modifier onlyNodeOwner(bytes32 node) {
        require(msg.sender == registry.owner(node));
        _;
    }

    // DnsResolver requires the ENS registry to confirm ownership of nodes
    constructor(AbstractENS _registry) public PublicResolver(_registry) {
        registry = _registry;
    }

    // 0xa8fa5682 == bytes4(keccak256("dnsRecord(bytes32,bytes32,uint16)"))
    // 0xdbfc5d00 == bytes4(keccak256("dnsZone(bytes32)"))
    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return interfaceId == 0xa8fa5682 || interfaceId == 0xdbfc5d00 || super.supportsInterface(interfaceId);
    }
    
    event Updated(bytes32 node, bytes name, uint16 resource, uint256 length);
    event Deleted(bytes32 node, bytes name, uint16 resource);
    function setDnsRecords(bytes32 node, bytes data) public onlyNodeOwner(node) {
        uint16 resource = 0;
        uint256 offset = 0;
        bytes memory name;
        bytes memory value;
        // Iterate over the data to add the resource records
        for(RRUtils.RRIterator memory iter = data.iterateRRs(0); !iter.done(); iter.next()) {
            if (resource == 0) {
                resource = iter.dnstype;
                name = bytes(iter.name());
                value = bytes(iter.rdata());
            } else {
                bytes memory newName = bytes(iter.name());
                if (resource != iter.dnstype || !name.equals(newName)) {
                    bytes memory rrData = data.substring(offset, iter.offset - offset);
                    if (value.length == 0) {
                        delete(records[node][keccak256(name)][resource]);
                        emit Deleted(node, name, resource);
                    } else {
                        records[node][keccak256(name)][resource] = rrData;
                        emit Updated(node, name, resource, rrData.length);
                    }
                    resource = iter.dnstype;
                    offset = iter.offset;
                    name = newName;
                    value = bytes(iter.rdata());
                }
            }
        }
        rrData = data.substring(offset, data.length - offset);
        if (value.length == 0) {
            delete(records[node][keccak256(name)][resource]);
            emit Deleted(node, name, resource);
        } else {
            records[node][keccak256(name)][resource] = rrData;
            emit Updated(node, name, resource, rrData.length);
        }
    }

    /**
     * Obtain a DNS record.
     * @param node the namehash of the node for which to fetch the record
     * @param name the keccak-256 hash of the fully-qualified name for which to fetch the record
     * @param resource the ID of the resource as per https://en.wikipedia.org/wiki/List_of_DNS_record_types
     * @return the DNS record in wire format if present, otherwise empty
     */
    function dnsRecord(bytes32 node, bytes32 name, uint16 resource) public view returns (bytes data) {
        return records[node][name][resource];
    }

    /**
     * Set the values for a DNS zone.
     * @param node the namehash of the node for which to store the zone
     * @param data the DNS zone in wire format
     */
    function setDnsZone(bytes32 node, bytes data) public onlyNodeOwner(node) {
        zones[node] = data;
    }

    /**
     * Obtain a DNS zone.
     * @param node the namehash of the node for which to fetch the zone
     * @return the DNS zone in wire format if present, otherwise empty
     */
    function dnsZone(bytes32 node) public view returns (bytes data) {
        return zones[node];
    }

    /**
     * Clear the values for a DNS zone.
     * @param node the namehash of the node for which to clear the zone
     */
    function clearDnsZone(bytes32 node) public onlyNodeOwner(node) {
        delete(zones[node]);
    }
}
