package com.socialmedia.chats.entity;

import jakarta.persistence.*;
import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Data;

import java.time.Instant;

@Entity
@Table(name = "call_logs")
public class CallLog {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "initiator_id")
    @JsonProperty("fromUserId")
    private Long initiatorId;
    
    @Column(name = "receiver_id")
    @JsonProperty("toUserId")
    private Long receiverId;

    // Set instead of receiverId for group calls — the conversation (group)
    // being called. Null for 1:1 calls.
    @Column(name = "group_id")
    private Long groupId;

    @Column(name = "call_type")
    private String callType; // AUDIO or VIDEO

    // Agora channel name — persisted so a call can be rejoined ("join later")
    // or looked up as "the active call for group X" after the initiator's
    // in-memory state is gone.
    @Column(name = "channel_name")
    private String channelName;

    // INITIATED, RINGING, ACCEPTED, ACTIVE (in-progress group call), ENDED,
    // DECLINED, MISSED, CANCELED, BUSY
    private String status;
    
    @Column(name = "duration_seconds")
    private Long duration; // duration in seconds
    
    @Column(name = "deleted_for_initiator")
    private Boolean deletedForInitiator = false;
    
    @Column(name = "deleted_for_receiver")
    private Boolean deletedForReceiver = false;
    
    @Column(name = "created_at")
    private Instant createdAt = Instant.now();
    
    @Column(name = "updated_at")
    private Instant updatedAt = Instant.now();

    public CallLog() {}

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public Long getInitiatorId() { return initiatorId; }
    public void setInitiatorId(Long initiatorId) { this.initiatorId = initiatorId; }

    public Long getReceiverId() { return receiverId; }
    public void setReceiverId(Long receiverId) { this.receiverId = receiverId; }

    public Long getGroupId() { return groupId; }
    public void setGroupId(Long groupId) { this.groupId = groupId; }

    public String getCallType() { return callType; }
    public void setCallType(String callType) { this.callType = callType; }
    
    public String getType() { return callType; } // Alias for backward compatibility
    public void setType(String type) { this.callType = type; }

    public String getChannelName() { return channelName; }
    public void setChannelName(String channelName) { this.channelName = channelName; }

    public String getStatus() { return status; }
    public void setStatus(String status) { 
        this.status = status; 
        this.updatedAt = Instant.now();
    }

    public Long getDuration() { return duration; }
    public void setDuration(Long duration) { 
        this.duration = duration;
        this.updatedAt = Instant.now();
    }

    public Boolean getDeletedForInitiator() { return deletedForInitiator; }
    public void setDeletedForInitiator(Boolean deletedForInitiator) { this.deletedForInitiator = deletedForInitiator; }

    public Boolean getDeletedForReceiver() { return deletedForReceiver; }
    public void setDeletedForReceiver(Boolean deletedForReceiver) { this.deletedForReceiver = deletedForReceiver; }

    public Instant getCreatedAt() { return createdAt; }
    public void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }

    public Instant getUpdatedAt() { return updatedAt; }
    public void setUpdatedAt(Instant updatedAt) { this.updatedAt = updatedAt; }
}