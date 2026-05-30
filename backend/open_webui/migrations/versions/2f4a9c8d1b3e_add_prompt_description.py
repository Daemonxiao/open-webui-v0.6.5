"""Add prompt description

Revision ID: 2f4a9c8d1b3e
Revises: a0b1c2d3e4f5
Create Date: 2026-05-29 00:00:00.000000

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = '2f4a9c8d1b3e'
down_revision: Union[str, None] = 'a0b1c2d3e4f5'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('prompt', sa.Column('description', sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column('prompt', 'description')
