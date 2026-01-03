/**
 * ReelForge Comment
 *
 * Comment/reply thread component:
 * - Avatar
 * - Author info
 * - Actions
 * - Nested replies
 * - Timestamps
 *
 * @module comment/Comment
 */

import './Comment.css';

// ============ Types ============

export interface CommentAction {
  key: string;
  label: React.ReactNode;
  onClick?: () => void;
}

export interface CommentProps {
  /** Author name */
  author?: React.ReactNode;
  /** Avatar element */
  avatar?: React.ReactNode;
  /** Comment content */
  content: React.ReactNode;
  /** Timestamp */
  datetime?: React.ReactNode;
  /** Action buttons */
  actions?: CommentAction[];
  /** Nested comments */
  children?: React.ReactNode;
  /** Custom class */
  className?: string;
}

export interface CommentListProps {
  /** Comments data */
  comments: CommentData[];
  /** Render item */
  renderItem?: (comment: CommentData) => React.ReactNode;
  /** Custom class */
  className?: string;
}

export interface CommentData {
  id: string;
  author: string;
  avatar?: string;
  content: string;
  datetime: string;
  likes?: number;
  replies?: CommentData[];
}

// ============ Comment Component ============

export function Comment({
  author,
  avatar,
  content,
  datetime,
  actions,
  children,
  className = '',
}: CommentProps) {
  return (
    <div className={`comment ${className}`}>
      <div className="comment__inner">
        {avatar && <div className="comment__avatar">{avatar}</div>}

        <div className="comment__body">
          <div className="comment__header">
            {author && <span className="comment__author">{author}</span>}
            {datetime && <span className="comment__datetime">{datetime}</span>}
          </div>

          <div className="comment__content">{content}</div>

          {actions && actions.length > 0 && (
            <div className="comment__actions">
              {actions.map((action) => (
                <button
                  key={action.key}
                  type="button"
                  className="comment__action"
                  onClick={action.onClick}
                >
                  {action.label}
                </button>
              ))}
            </div>
          )}
        </div>
      </div>

      {children && <div className="comment__replies">{children}</div>}
    </div>
  );
}

// ============ CommentAvatar Component ============

export interface CommentAvatarProps {
  src?: string;
  alt?: string;
  children?: React.ReactNode;
  size?: number;
  className?: string;
}

export function CommentAvatar({
  src,
  alt = '',
  children,
  size = 36,
  className = '',
}: CommentAvatarProps) {
  const style = { width: size, height: size };

  if (src) {
    return (
      <img
        src={src}
        alt={alt}
        className={`comment-avatar ${className}`}
        style={style}
      />
    );
  }

  return (
    <div className={`comment-avatar comment-avatar--placeholder ${className}`} style={style}>
      {children || alt.charAt(0).toUpperCase()}
    </div>
  );
}

// ============ CommentList Component ============

export function CommentList({
  comments,
  renderItem,
  className = '',
}: CommentListProps) {
  const defaultRender = (comment: CommentData) => (
    <Comment
      key={comment.id}
      author={comment.author}
      avatar={
        <CommentAvatar src={comment.avatar} alt={comment.author} />
      }
      content={comment.content}
      datetime={comment.datetime}
      actions={[
        { key: 'like', label: `Like${comment.likes ? ` (${comment.likes})` : ''}` },
        { key: 'reply', label: 'Reply' },
      ]}
    >
      {comment.replies && comment.replies.length > 0 && (
        <CommentList comments={comment.replies} renderItem={renderItem} />
      )}
    </Comment>
  );

  return (
    <div className={`comment-list ${className}`}>
      {comments.map((comment) =>
        renderItem ? renderItem(comment) : defaultRender(comment)
      )}
    </div>
  );
}

// ============ CommentEditor Component ============

export interface CommentEditorProps {
  /** Current value */
  value?: string;
  /** On change */
  onChange?: (value: string) => void;
  /** On submit */
  onSubmit?: () => void;
  /** Placeholder */
  placeholder?: string;
  /** Submit text */
  submitText?: string;
  /** Avatar */
  avatar?: React.ReactNode;
  /** Loading state */
  loading?: boolean;
  /** Custom class */
  className?: string;
}

export function CommentEditor({
  value = '',
  onChange,
  onSubmit,
  placeholder = 'Write a comment...',
  submitText = 'Post',
  avatar,
  loading = false,
  className = '',
}: CommentEditorProps) {
  return (
    <div className={`comment-editor ${className}`}>
      {avatar && <div className="comment-editor__avatar">{avatar}</div>}

      <div className="comment-editor__body">
        <textarea
          className="comment-editor__input"
          value={value}
          onChange={(e) => onChange?.(e.target.value)}
          placeholder={placeholder}
          rows={3}
        />

        <div className="comment-editor__footer">
          <button
            type="button"
            className="comment-editor__submit"
            onClick={onSubmit}
            disabled={!value.trim() || loading}
          >
            {loading ? 'Posting...' : submitText}
          </button>
        </div>
      </div>
    </div>
  );
}

export default Comment;
