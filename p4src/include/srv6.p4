/* Copyright 2017-present Kentaro Ebisawa <ebiken.g@gmail.com>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/* Written in P4_14 */
/* SRv6 related headers and actions are defined in this file */

///// HEADER //////////////////////////////////////////////
// draft-ietf-6man-segment-routing-header-10
// 3. Segment Routing Extension Header (SRH)
// Optional TLV not defined (yet) for simplisity.
header_type ipv6_srh_t {
    fields {
		nextHeader   : 8;
		hdrExtLen    : 8;
		routingType  : 8;
		segmentsLeft : 8;
		lastEntry    : 8;
		flags        : 8;
		tag          : 16;
	}
}
header ipv6_srh_t ipv6_srh;

header_type ipv6_srh_segment_t {
	fields {
		sid : 128;
	}
}
#define SRH_MAX_SEGMENTS 3
// +1 for inline mode
header ipv6_srh_segment_t ipv6_srh_segment_list[SRH_MAX_SEGMENTS+1];

///// PARSER //////////////////////////////////////////////
parser parse_ipv6_srh {
	extract(ipv6_srh);
	return parse_ipv6_srh_seg0;
}
parser parse_ipv6_srh_seg0 {
	extract(ipv6_srh_segment_list[0]);
	return select(ipv6_srh.lastEntry) {
		//0 : ingress;
		0 : parse_ipv6_srh_payload;
		default: parse_ipv6_srh_seg1;
	}
}
parser parse_ipv6_srh_seg1 {
	extract(ipv6_srh_segment_list[1]);
	return select(ipv6_srh.lastEntry) {
		//1 : ingress;
		1 : parse_ipv6_srh_payload;
		default: parse_ipv6_srh_seg2;
	}
}
parser parse_ipv6_srh_seg2 {
	extract(ipv6_srh_segment_list[2]);
	return select(ipv6_srh.lastEntry) {
		//2 : ingress;
		2 : parse_ipv6_srh_payload;
		default: parse_ipv6_srh_seg3;
	}
}
parser parse_ipv6_srh_seg3 {
	extract(ipv6_srh_segment_list[3]);
	// SRH_MAX_SEGMENTS +1 = 4 so this is the last segment in the list.
	//return ingress;
	return parse_ipv6_srh_payload;
}
parser parse_ipv6_srh_payload {
	return select(ipv6_srh.nextHeader) {
		//IP_PROTOCOLS_ICMP : parse_icmp;
		IP_PROTOCOLS_IPV4 : parse_ipv4;
		IP_PROTOCOLS_TCP  : parse_tcp;
		IP_PROTOCOLS_UDP  : parse_udp;
		IP_PROTOCOLS_IPV6 : parse_ipv6_inner;
		default: ingress;
	}
}
parser parse_ipv6_inner {
	extract(ipv6_inner);
	return ingress;
}

///// ACTION //////////////////////////////////////////////
action ipv6_srh_insert(proto) {
	add_header(ipv6_srh);
	modify_field(ipv6_srh.nextHeader, proto);
	modify_field(ipv6_srh.hdrExtLen, 0);
	modify_field(ipv6_srh.routingType, 4);
	modify_field(ipv6_srh.segmentsLeft, 0);
	modify_field(ipv6_srh.lastEntry, 0);
	modify_field(ipv6_srh.flags, 0);
	modify_field(ipv6_srh.tag, 0);
}

// original ipv6 will be copied to ipv6_inner.
// ipv6 will be new outer ipv6 header.
action ipv6_encap_ipv6(srcAddr, dstAddr) {
	// ipv6_inner is actually original header. copy it.
	add_header(ipv6_inner);
	copy_header(ipv6_inner, ipv6);
	// update original (outer) header
	add_to_field(ipv6.payloadLen, 20); // size of ipv6_inner
	modify_field(ipv6.nextHdr, IP_PROTOCOLS_IPV6);
	modify_field(ipv6.srcAddr, srcAddr);
	modify_field(ipv6.dstAddr, dstAddr);
}
	

//// SRv6 Functions
// For "inline" mode:
// 1. dstAddr of received packet will be added to the last segment to traverse (seg[0])
// 2. dstAddr will be modified to the fist segment to traverse (seg[n])
action srv6_T_Insert1(sid0) {
    ipv6_srh_insert(ipv6.nextHdr);
    add_header(ipv6_srh_segment_list[0]);
    modify_field(ipv6_srh_segment_list[0].sid, ipv6.dstAddr);
    add_header(ipv6_srh_segment_list[1]);
    modify_field(ipv6_srh_segment_list[1].sid, sid0);
    modify_field(ipv6_srh.hdrExtLen, 4); // TODO
    modify_field(ipv6_srh.segmentsLeft, 1);
    modify_field(ipv6_srh.lastEntry, 1);
    // update original ipv6 headers
    modify_field(ipv6.nextHdr, IP_PROTOCOLS_SRV6);
    modify_field(ipv6.dstAddr, sid0);
    add_to_field(ipv6.payloadLen, 8+16*2); // SRH(8)+Seg(16)*2
}
action srv6_T_Insert2(sid0, sid1) {
    ipv6_srh_insert(ipv6.nextHdr);
    add_header(ipv6_srh_segment_list[0]);
    modify_field(ipv6_srh_segment_list[0].sid, ipv6.dstAddr);
    add_header(ipv6_srh_segment_list[1]);
    modify_field(ipv6_srh_segment_list[1].sid, sid1);
    add_header(ipv6_srh_segment_list[2]);
    modify_field(ipv6_srh_segment_list[2].sid, sid0);
    modify_field(ipv6_srh.hdrExtLen, 6);
    modify_field(ipv6_srh.segmentsLeft, 2);
    modify_field(ipv6_srh.lastEntry, 2);
    // update original ipv6 headers
    modify_field(ipv6.nextHdr, IP_PROTOCOLS_SRV6);
    modify_field(ipv6.dstAddr, sid0);
    add_to_field(ipv6.payloadLen, 8+16*3); // SRH(8)+Seg(16)*3
}
action srv6_T_Insert3(sid0, sid1, sid2) {
	ipv6_srh_insert(ipv6.nextHdr);
	add_header(ipv6_srh_segment_list[0]);
	modify_field(ipv6_srh_segment_list[0].sid, ipv6.dstAddr);
	add_header(ipv6_srh_segment_list[1]);
	modify_field(ipv6_srh_segment_list[1].sid, sid2);
	add_header(ipv6_srh_segment_list[2]);
	modify_field(ipv6_srh_segment_list[2].sid, sid1);
	add_header(ipv6_srh_segment_list[3]);
	modify_field(ipv6_srh_segment_list[3].sid, sid0);
	modify_field(ipv6_srh.hdrExtLen, 8);
	modify_field(ipv6_srh.segmentsLeft, 3);
	modify_field(ipv6_srh.lastEntry, 3);
	// update original ipv6 headers
	modify_field(ipv6.nextHdr, IP_PROTOCOLS_SRV6);
	modify_field(ipv6.dstAddr, sid0);
	add_to_field(ipv6.payloadLen, 8+16*4); // SRH(8)+Seg(16)*4
}

action srv6_T_Encap1(srcAddr, sid0) {
	ipv6_encap_ipv6(srcAddr, sid0); // dstAddr==sid0
	ipv6_srh_insert(IP_PROTOCOLS_IPV6);
	add_header(ipv6_srh_segment_list[0]);
	modify_field(ipv6_srh_segment_list[0].sid, sid0);
    modify_field(ipv6_srh.hdrExtLen, 2); // 2bytes*(number of seg)
    modify_field(ipv6_srh.segmentsLeft, 0);
    modify_field(ipv6_srh.lastEntry, 0);
	// update original ipv6 headers
	modify_field(ipv6.nextHdr, IP_PROTOCOLS_SRV6);
	modify_field(ipv6.dstAddr, sid0);
	add_to_field(ipv6.payloadLen, 8+16*1); // SRH(8)+Seg(16)*1
}
action srv6_T_Encap2(srcAddr, sid0, sid1) {
	ipv6_encap_ipv6(srcAddr, sid0); // dstAddr==sid0
	ipv6_srh_insert(IP_PROTOCOLS_IPV6);
	modify_field(ipv6.nextHdr, IP_PROTOCOLS_SRV6);
	add_header(ipv6_srh_segment_list[0]);
	modify_field(ipv6_srh_segment_list[0].sid, sid1);
	add_header(ipv6_srh_segment_list[1]);
	modify_field(ipv6_srh_segment_list[1].sid, sid0);
    modify_field(ipv6_srh.hdrExtLen, 4); // 2bytes*(number of seg)
    modify_field(ipv6_srh.segmentsLeft, 1);
    modify_field(ipv6_srh.lastEntry, 1);
	// update original ipv6 headers
	modify_field(ipv6.nextHdr, IP_PROTOCOLS_SRV6);
	modify_field(ipv6.dstAddr, sid0);
	add_to_field(ipv6.payloadLen, 8+16*2); // SRH(8)+Seg(16)*2
}
action srv6_T_Encap3(srcAddr, sid0, sid1, sid2) {
	ipv6_encap_ipv6(srcAddr, sid0); // dstAddr==sid0
	ipv6_srh_insert(IP_PROTOCOLS_IPV6);
	modify_field(ipv6.nextHdr, IP_PROTOCOLS_SRV6);
	add_header(ipv6_srh_segment_list[0]);
	modify_field(ipv6_srh_segment_list[0].sid, sid2);
	add_header(ipv6_srh_segment_list[1]);
	modify_field(ipv6_srh_segment_list[1].sid, sid1);
	add_header(ipv6_srh_segment_list[2]);
	modify_field(ipv6_srh_segment_list[2].sid, sid0);
    modify_field(ipv6_srh.hdrExtLen, 6); // 2bytes*(number of seg)
    modify_field(ipv6_srh.segmentsLeft, 2);
    modify_field(ipv6_srh.lastEntry, 2);
	// update original ipv6 headers
	modify_field(ipv6.nextHdr, IP_PROTOCOLS_SRV6);
	modify_field(ipv6.dstAddr, sid0);
	add_to_field(ipv6.payloadLen, 8+16*3); // SRH(8)+Seg(16)*3
}

